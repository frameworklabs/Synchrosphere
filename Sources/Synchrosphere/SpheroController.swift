// Project Synchrosphere
// Copyright 2021, Framework Labs.

import Pappe

/// Provides the robots functionality as activities.
final class SpheroController {
    
    private let context: ControllerContext
    var endpoint: Endpoint!
    
    init(context: ControllerContext) {
        self.context = context
    }
    
    func makeModule(imports: [Module.Import]) -> Module {
        return Module(imports: imports) { name in
            
            // MARK: Power
            
            activity (name.Wake_, []) { val in
                exec {
                    self.context.logInfo("Wake")
                    val.id = self.endpoint.send(PowerCommand.wake)
                }
                await { self.endpoint.hasResponse(for: val.id) }
            }

            activity (name.Sleep_, []) { val in
                exec {
                    self.context.logInfo("Sleep")
                    val.id = self.endpoint.send(PowerCommand.sleep)                    
                }
                await { self.endpoint.hasResponse(for: val.id) }
            }
            
            activity (Syncs.GetBatteryState, []) { val in
                exec {
                    self.context.logInfo("GetBatteryState")
                    val.id = self.endpoint.send(PowerCommand.getBatteryState)
                }
                await { self.endpoint.hasResponse(for: val.id) { response in
                    do {
                        let state = try parseGetBatteryStateResponse(response)
                        val.state = state
                        self.context.logInfo("GetBatteryState = \(state)")
                    } catch  {
                        val.state = nil as SyncsBatteryState?
                        self.context.logError("GetBatteryState failed with: \(error)")
                    }
                } }
                `return` { val.state }
            }
                   
            // MARK: IO
            
            activity (Syncs.SetMainLED, [name.color]) { val in
                exec {
                    let color: SyncsColor = val.color
                    
                    self.context.logInfo("SetMainLED \(color)")
                    val.id = self.endpoint.send(SetMainLEDRequest(color: color))
                }
                await { self.endpoint.hasResponse(for: val.id) }
            }
            
            activity (Syncs.SetBackLED, [name.brightness]) { val in
                exec {
                    let brightness: SyncsBrightness = val.brightness
                    
                    self.context.logInfo("SetLBackLED \(brightness)")
                    val.id = self.endpoint.send(SetBackLEDRequest(brightness: brightness))
                }
                await { self.endpoint.hasResponse(for: val.id) }
            }
            
            // MARK: Drive
            
            activity (Syncs.ResetHeading, []) { val in
                exec {
                    self.context.logInfo("ResetHeading")
                    val.id = self.endpoint.send(DriveCommand.resetHeading)
                }
                await { self.endpoint.hasResponse(for: val.id) }
            }

            activity (Syncs.Roll, [name.speed, name.heading, name.dir]) { val in
                exec {
                    let speed: SyncsSpeed = val.speed
                    let heading: SyncsHeading = val.heading
                    let dir: SyncsDir = val.dir
                    
                    self.context.logInfo("Roll speed: \(speed) heading: \(heading) dir: \(dir)")
                    val.id = self.endpoint.send(RollRequest(speed: speed, heading: heading, dir: dir))
                }
                await { self.endpoint.hasResponse(for: val.id) }
            }
            
            activity (Syncs.RollForSeconds, [name.speed, name.heading, name.dir, name.seconds]) { val in
                exec { self.context.logInfo("RollForSeconds \(val.seconds as Int)s") }
                cobegin {
                    strong {
                        run (Syncs.WaitSeconds, [val.seconds])
                    }
                    weak {
                        `repeat` {
                            run (Syncs.Roll, [val.speed, val.heading, val.dir])
                            run (Syncs.WaitSeconds, [2]) // The control timeout is 2s
                        }
                    }
                }
                run (Syncs.StopRoll, [val.heading])
            }

            activity (Syncs.StopRoll, [name.heading]) { val in
                exec {
                    let heading: SyncsHeading = val.heading
                    
                    self.context.logInfo("StopRoll")
                    val.id = self.endpoint.send(RollRequest(speed: SyncsSpeed(0), heading: heading, dir: .forward))
                }
                await { self.endpoint.hasResponse(for: val.id) }
            }
            
            // MARK: Sensor
            
            activity (Syncs.ResetLocator, []) { val in
                exec {
                    self.context.logInfo("ResetLocator")
                    val.id = self.endpoint.send(SensorCommand.resetLocator)
                }
                await { self.endpoint.hasResponse(for: val.id) }
            }
            
            activity (Syncs.SensorStreamer, [name.frequency, name.sensors], [name.sample]) { val in
                exec {
                    let frequency: Int = val.frequency
                    let period: UInt16 = UInt16(1000) / UInt16(frequency)
                    let sensors: SyncsSensors = val.sensors
                    
                    self.context.logInfo("SensorStreamer \(frequency)hz \(sensors)")
                    val.id = self.endpoint.send(StartSensorStreamingRequest(period: period, sensors: sensors))
                }
                await { self.endpoint.hasResponse(for: val.id) }
                `defer` { self.context.requests_.stopSensorStreaming() }
                `repeat` {
                    await { self.context.clock.tick && self.endpoint.hasResponse(for: RequestID(command: SensorCommand.notifySensorData, sequenceNr: sensorDataSequenceNr)) { response in
                        do {
                            let timestamp = self.context.clock.counter
                            let sensors: SyncsSensors = val.sensors
                            val.sample = try parseStreamedSampleResponse(response, timestamp: timestamp, sensors: sensors)
                        } catch {
                            self.context.logError("getting streaming sample failed with: \(error)V")
                        }
                    } }
                }
            }

            activity (name.StopSensorStreaming_, []) { val in
                exec {
                    self.context.logInfo("StopSensorStreaming")
                    val.id = self.endpoint.send(StopSensorStreamingRequest())
                }
                await { self.endpoint.hasResponse(for: val.id) }
            }
        }
    }
}
