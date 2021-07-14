// Project Synchrosphere
// Copyright 2021, Framework Labs.

/// Implementation of the `SyncsRequest` protocol.
///
/// In addition to the methods defined in the protocol, some more request methods needed internally are provided here.
final class Requests : SyncsRequests, SyncsLogging, LoggingProviderAccessor {
            
    let loggingProvider: SyncsLogging
    let deviceSelector: SyncsDeviceSelector
    private var endpoint: Endpoint!

    init(loggingProvider: SyncsLogging, deviceSelector: SyncsDeviceSelector) {
        self.loggingProvider = loggingProvider
        self.deviceSelector = deviceSelector
    }

    func set(_ endpoint: Endpoint?) {
        self.endpoint = endpoint
    }
    
    // MARK: Power
    
    func wake() {
        logInfo("requestWake")
        endpoint.sendOneway(PowerCommand.wake, to: 1)
    }
    
    func sleep() {
        logInfo("requestSleep")
        endpoint.sendOneway(PowerCommand.sleep, to: 1)
    }

    // MARK: IO
    
    func setMainLED(to color: SyncsColor) {
        logInfo("requestSetMainLED \(color)")
        if deviceSelector == .anyRVR {
            endpoint.sendOneway(SetAllLEDsRequest(mapping: [SyncsRVRLEDs.all: color]))
        }
        else {
            endpoint.sendOneway(SetMainLEDRequest(color: color))
        }
    }
    
    func setBackLED(to brightness: SyncsBrightness) {
        logInfo("requestSetBackLED \(brightness)")
        if deviceSelector == .anyRVR {
            endpoint.sendOneway(SetAllLEDsRequest(mapping: [.breaklight: SyncsColor(brightness: brightness)]))
        }
        else {
            endpoint.sendOneway(SetBackLEDRequest(brightness: brightness))
        }
    }
    
    func setRVRLEDs(_ mapping: [SyncsRVRLEDs: SyncsColor]) {
        logInfo("setRVRLEDs")
        endpoint.sendOneway(SetAllLEDsRequest(mapping: mapping))
    }
    
    // MARK: Drive
    
    func stopRoll(towards heading: SyncsHeading) {
        logInfo("requestStopRoll")
        endpoint.sendOneway(RollRequest(speed: SyncsSpeed(0), heading: heading, dir: .forward))
    }
    
    // MARK: Sensor
        
    func stopSensorStreaming() {
        logInfo("requestStopSensorStreaming")
        if deviceSelector == .anyRVR {
            endpoint.sendOneway(SensorCommand.stopStreamingService, to: 2)
            endpoint.sendOneway(SensorCommand.clearStreamingService, to: 2)
        }
        else {
            endpoint.sendOneway(StopSensorStreamingRequest())
        }
    }
}
