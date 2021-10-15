// Project Synchrosphere
// Copyright 2021, Framework Labs.

import Pappe

/// The class which orchestrates the control of the robot; delegates to other controllers for specific tasks.
final class MainController : SyncsController {
    
    private let context_: ControllerContext
    private var startRequested = false
    private var stopRequested = false
    private let timerController: TimerController
    private let centralManagerController: CentralManagerController
    private let peripheralController: PeripheralController
    private let spheroController: SpheroController

    var context: SyncsControllerContext {
        return context_
    }

    init(config: SyncsControllerConfig, @ActivityBuilder builder: (ID, SyncsControllerContext) -> [Activity]) {

        // Setup context.
        context_ = ControllerContext(config: config)
        
        // Create controllers.
        timerController = TimerController(context: context_)
        centralManagerController = CentralManagerController(context: context_)
        peripheralController = PeripheralController(context: context_)
        spheroController = SpheroController(context: context_)
        
        // Create code modules from controllers.
        let timerModule = timerController.makeModule(imports: [])
        let centralManagerModule = centralManagerController.makeModule(imports: [])
        let peripheralModule = peripheralController.makeModule(imports: [])
        let spheroModule = spheroController.makeModule(imports: [timerModule])
        let clientModule = Module(imports: [timerModule, spheroModule] + config.imports) { name in
            return builder(name, context)
        }
        let mainControllerModule = makeModule(imports: [
            timerModule,
            centralManagerModule,
            peripheralModule,
            spheroModule,
            clientModule
        ])
        
        // Make processor and store in context.
        context_.processor = try! Processor(module: mainControllerModule, entryPoint: "Main_")
    }
        
    private func makeModule(imports: [Module.Import]) -> Module {
        Module(imports: imports) { name in
            
            activity (name.Main_, []) { val in
                `repeat` {
                    
                    // Wait for start requested.
                    `if` { !self.startRequested } then: {
                        `await` { self.startRequested }
                    }
                    exec {
                        self.startRequested = false
                        self.context.setState(.isRunning)
                    }
                    
                    when { self.stopRequested } abort: {
                        
                        // Wait for Bluetooth availability.
                        `if` { !self.centralManagerController.isBluetoothAvailable } then: {
                            `await` { self.centralManagerController.isBluetoothAvailable }
                        }
                        exec { self.context.setState(.isBluetoothAvailable) }
                        `defer` { self.context.clearState(.isBluetoothAvailable) }
                        
                        when { !self.centralManagerController.isBluetoothAvailable } abort: {
                            
                            // Scan for peripheral.
                            exec { self.context.setState(.isScanning) }
                            `defer` { self.context.clearState(.isScanning)}
                            run (name.ScanForPeripheral_, [self.context.config.deviceSelector])
                            exec { self.context.clearState(.isScanning)}
                            
                            exec { self.context.setState(.foundDevice) }
                            `defer` { self.context.clearState(.foundDevice) }
                            
                            // Connect peripheral.
                            exec { self.context.setState(.isConnecting) }
                            `defer` { self.context.clearState(.isConnecting) }
                            run (name.ConnectPeripheral_, [])
                            exec { self.context.clearState(.isConnecting) }

                            exec { self.context.setState(.isConnected) }
                            `defer` { self.context.clearState(.isConnected) }
                            // Unfortunately, we cant disconnect in defer as otherwise `requestSleep` will
                            // not be able to complete correctly. But putting device to sleep is more important here.
                            
                            when { !self.centralManagerController.isPeripheralConnected } abort: {
                                
                                // Inform sub-controllers about peripheral and endpoint
                                exec {
                                    self.peripheralController.peripheral = self.centralManagerController.peripheral

                                    let endpoint = self.peripheralController.endpoint
                                    self.context_.requests_.set(endpoint)
                                    self.spheroController.endpoint = endpoint
                                }
                                
                                // Introspect peripheral.
                                exec { self.context.setState(.isIntrospecting) }
                                `defer` { self.context.clearState(.isIntrospecting) }
                                run (name.DiscoverPeripheralCharacteristics_, [])
                                exec { self.context.clearState(.isIntrospecting) }

                                // Unlock it with the force.
                                run (name.UnlockPeripheral_, [])
                                
                                // Start clock timers.
                                exec { self.timerController.startTimer() }
                                `defer` { self.timerController.stopTimer() }

                                // Wake up device.
                                run (name.Wake_, [])
                                exec { self.context.setState(.isAwake) }
                                `defer` {
                                    self.context_.requests_.stopRoll(towards: SyncsHeading(0))
                                    self.context_.requests_.stopSensorStreaming()
                                    self.context_.requests_.sleep()
                                    self.context.clearState(.isAwake)
                                }
                                
                                // Wait 200ms for device to wake up - set led to black.
                                run (Syncs.WaitMilliseconds, [200])
                                run (Syncs.SetMainLED, [SyncsColor.black])

                                // Call users Main activity - either with battery monitor or directly.
                                `if` { self.context.config.batteryCheckTicks > 0 } then: {
                                    run (name.BatteryMonitoringMainExecutor_, [])
                                } else: {
                                    run (name.Main, [])
                                }
                                
                                // Stop device rolling and streaming data.
                                cobegin {
                                    with {
                                        run (Syncs.StopRoll, [SyncsHeading(0)])
                                        run (Syncs.WaitSeconds, [1])
                                    }
                                    with {
                                        run (name.StopSensorStreaming_, [])
                                    }
                                }

                                // Set device to soft sleep.
                                run (name.Sleep_, [])
                                exec { self.context.clearState(.isAwake) }
                            }
                        }
                    }
                    
                    // Disconnect.
                    `if` { self.centralManagerController.isBluetoothAvailable && self.centralManagerController.isPeripheralConnected } then: {
                        
                        // Wait for some short time so that sleep request will be processed.
                        exec { self.timerController.startTimer() }
                        `defer` { self.timerController.stopTimer() }
                        run (Syncs.WaitMilliseconds, [500])

                        run (name.DisconnectPeripheral_, [])
                    }
                    
                    exec {
                        self.stopRequested = false
                        self.context.clearState(.isRunning)
                    }
                }
            }
            
            activity (name.BatteryMonitoringMainExecutor_, []) { val in
                exec {
                    val.batteryState = SyncsBatteryState.ok
                    val.isMainFinished = false
                }
                `defer` {
                    self.context.setState(from: .ok)
                }
                cobegin {
                    with (.weak) {
                        `repeat` {
                            run (Syncs.GetBatteryState, []) { res in
                                guard let batteryState = res as? SyncsBatteryState else { return }
                                val.batteryState = batteryState
                                self.context.setState(from: batteryState)
                            }
                            `await` { self.context.clock.tick(downBy: self.context.config.batteryCheckTicks) }
                        }
                    }
                    with {
                        when { val.batteryState != SyncsBatteryState.ok } abort: {
                            run (name.Main, [])
                            exec { val.isMainFinished = true }
                        }
                    }
                }
                `if` { !val.isMainFinished } then: {
                    exec { self.context.logInfo("handling battery too low case") }
                    `repeat` {
                        run (Syncs.SetMainLED, [SyncsColor.red])
                        `await` { self.context.clock.tick(downBy: 5) }
                        run (Syncs.SetMainLED, [SyncsColor.black])
                        `await` { self.context.clock.tick(downBy: 10) }
                    }
                }
            }            
        }
    }
    
    func start() {
        guard !context.state.contains(.isRunning) else {
            context.logInfo("can't start - already running")
            return
        }
        context.logInfo("start")
        startRequested = true
        stopRequested = false
        context.trigger()
    }
    
    func stop() {
        guard context.state.contains(.isRunning) else {
            context.logInfo("can't stop - not running")
            return
        }
        context.logInfo("stop")
        startRequested = false
        stopRequested = true
        context.trigger()
    }    
}
