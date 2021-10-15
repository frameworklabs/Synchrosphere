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
                    val.id = self.endpoint.send(PowerCommand.wake, to: 1)
                }
                `await` { self.endpoint.hasResponse(for: val.id) }
            }

            activity (name.Sleep_, []) { val in
                exec {
                    self.context.logInfo("Sleep")
                    val.id = self.endpoint.send(PowerCommand.sleep, to: 1)
                }
                `await` { self.endpoint.hasResponse(for: val.id) }
            }
            
            activity (Syncs.GetBatteryState, []) { val in
                exec {
                    self.context.logInfo("GetBatteryState")
                    val.id = self.endpoint.send(PowerCommand.getBatteryState, to: 1)
                }
                `await` { self.endpoint.hasResponse(for: val.id) { response in
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
                    if self.context.config.deviceSelector == .anyRVR {
                        val.id = self.endpoint.send(SetAllLEDsRequest(mapping: [SyncsRVRLEDs.all: color]))
                    }
                    else {
                        val.id = self.endpoint.send(SetMainLEDRequest(color: color))
                    }
                }
                `await` { self.endpoint.hasResponse(for: val.id) }
            }
            
            activity (Syncs.SetBackLED, [name.brightness]) { val in
                exec {
                    let brightness: SyncsBrightness = val.brightness
                    
                    self.context.logInfo("SetLBackLED \(brightness)")
                    if self.context.config.deviceSelector == .anyRVR {
                        val.id = self.endpoint.send(SetAllLEDsRequest(mapping: [.breaklight: SyncsColor(brightness: brightness)]))
                    }
                    else {
                        val.id = self.endpoint.send(SetBackLEDRequest(brightness: brightness))
                    }
                }
                `await` { self.endpoint.hasResponse(for: val.id) }
            }

            activity (Syncs.SetRVRLEDs, [name.mapping]) { val in
                exec {
                    let mapping: [SyncsRVRLEDs: SyncsColor] = val.mapping
                    
                    self.context.logInfo("SetRVRLEDs")
                    val.id = self.endpoint.send(SetAllLEDsRequest(mapping: mapping))
                }
                `await` { self.endpoint.hasResponse(for: val.id) }
            }

            // MARK: Drive
            
            activity (Syncs.ResetHeading, []) { val in
                exec {
                    self.context.logInfo("ResetHeading")
                    val.id = self.endpoint.send(DriveCommand.resetHeading, to: 2)
                }
                `await` { self.endpoint.hasResponse(for: val.id) }
            }

            activity (Syncs.Roll, [name.speed, name.heading, name.dir]) { val in
                exec {
                    let speed: SyncsSpeed = val.speed
                    let heading: SyncsHeading = val.heading
                    let dir: SyncsDir = val.dir
                    
                    self.context.logInfo("Roll speed: \(speed) heading: \(heading) dir: \(dir)")
                    val.id = self.endpoint.send(RollRequest(speed: speed, heading: heading, dir: dir))
                }
                `await` { self.endpoint.hasResponse(for: val.id) }
            }
            
            activity (Syncs.RollForSeconds, [name.speed, name.heading, name.dir, name.seconds]) { val in
                exec { self.context.logInfo("RollForSeconds \(val.seconds as Int)s") }
                cobegin {
                    with {
                        run (Syncs.WaitSeconds, [val.seconds])
                    }
                    with (.weak) {
                        `repeat` {
                            run (Syncs.Roll, [val.speed, val.heading, val.dir])
                            run (Syncs.WaitSeconds, [1]) // The control timeout is 2s - so we are safe with 1
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
                `await` { self.endpoint.hasResponse(for: val.id) }
            }
            
            // MARK: Sensor
            
            activity (Syncs.ResetLocator, []) { val in
                exec {
                    self.context.logInfo("ResetLocator")
                    val.id = self.endpoint.send(SensorCommand.resetLocator, to: 2)
                }
                `await` { self.endpoint.hasResponse(for: val.id) }
            }

            activity (Syncs.SetLocatorFlags, [name.flags]) { val in
                exec {
                    let flags: SyncsLocatorFlags = val.flags
                    
                    self.context.logInfo("SetLocatorFlags \(flags)")
                    val.id = self.endpoint.send(SensorCommand.setLocatorFlags, with: [flags.rawValue], to: 2)
                }
                `await` { self.endpoint.hasResponse(for: val.id) }
            }

            activity (name.SensorStreamerRVR_, [name.frequency, name.sensors], [name.sample]) { val in
                exec {
                    let sensors: SyncsSensors = val.sensors
                    
                    val.id = self.endpoint.send(ConfigureStreamingServiceRequest(sensors: sensors))
                }
                `await` { self.endpoint.hasResponse(for: val.id) }
                exec {
                    let frequency: Int = val.frequency
                    let period: UInt16 = UInt16(1000) / UInt16(frequency)
                    
                    val.id = self.endpoint.send(StartStreamingServiceRequest(period: period))
                }
                `await` { self.endpoint.hasResponse(for: val.id) }
                `defer` { self.context.requests_.stopSensorStreaming() }
                `repeat` {
                    `await` {
                        self.endpoint.hasResponse(for: RequestID(command: SensorCommand.streamingServiceDataNotify, sequenceNr: sensorDataSequenceNr)) { response in
                            do {
                                let timestamp = self.context.clock.counter
                                let sensors: SyncsSensors = val.sensors
                                val.sample = try parseStreamingServiceDataNotifyResponse(response, timestamp: timestamp, sensors: sensors)
                            } catch {
                                self.context.logError("getting streaming sample failed with: \(error)V")
                            }
                        }
                    }
                }
            }

            activity (name.SensorStreamerMini_, [name.frequency, name.sensors], [name.sample]) { val in
                exec {
                    let frequency: Int = val.frequency
                    let period: UInt16 = UInt16(1000) / UInt16(frequency)
                    let sensors: SyncsSensors = val.sensors

                    self.context.logInfo("SensorStreamer \(frequency)hz \(sensors)")
                    val.id = self.endpoint.send(StartSensorStreamingRequest(period: period, sensors: sensors))
                }
                `await` { self.endpoint.hasResponse(for: val.id) }
                `defer` { self.context.requests_.stopSensorStreaming() }
                `repeat` {
                    `await` {
                        self.endpoint.hasResponse(for: RequestID(command: SensorCommand.notifySensorData, sequenceNr: sensorDataSequenceNr)) { response in
                            do {
                                let timestamp = self.context.clock.counter
                                let sensors: SyncsSensors = val.sensors
                                val.sample = try parseStreamedSampleResponse(response, timestamp: timestamp, sensors: sensors)
                            } catch {
                                self.context.logError("getting streaming sample failed with: \(error)V")
                            }
                        }
                    }
                }
            }

            activity (Syncs.SensorStreamer, [name.frequency, name.sensors], [name.sample]) { val in
                `if` { self.context.config.deviceSelector == .anyRVR } then: {
                    run (name.SensorStreamerRVR_, [val.frequency, val.sensors], [val.loc.sample])
                } else: {
                    run (name.SensorStreamerMini_, [val.frequency, val.sensors], [val.loc.sample])
                }
            }
   
            activity (name.StopSensorStreamingRVR_, []) { val in
                exec {
                    self.context.logInfo("StopSensorStreaming")
                    val.id = self.endpoint.send(SensorCommand.stopStreamingService, to: 2)
                }
                `await` { self.endpoint.hasResponse(for: val.id) }
                exec { val.id = self.endpoint.send(SensorCommand.clearStreamingService, to: 2) }
                `await` { self.endpoint.hasResponse(for: val.id) }
            }
            
            activity (name.StopSensorStreamingMini_, []) { val in
                exec {
                    self.context.logInfo("StopSensorStreaming")
                    val.id = self.endpoint.send(StopSensorStreamingRequest())
                }
                `await` { self.endpoint.hasResponse(for: val.id) }
            }
            
            activity (name.StopSensorStreaming_, []) { val in
                `if` { self.context.config.deviceSelector == .anyRVR } then: {
                    run (name.StopSensorStreamingRVR_, [])
                } else: {
                    run (name.StopSensorStreamingMini_, [])
                }
            }
        }
    }
}
