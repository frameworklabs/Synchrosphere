// Project Synchrosphere
// Copyright 2021, Framework Labs.

/// Implementation of the `SyncsRequest` protocol.
///
/// In addition to the methods defined in the protocol, some more request methods needed internally are provided here.
final class Requests : SyncsRequests, SyncsLogging, LoggingProviderAccessor {
            
    let loggingProvider: SyncsLogging
    private var endpoint: Endpoint!

    init(loggingProvider: SyncsLogging) {
        self.loggingProvider = loggingProvider
    }

    func set(_ endpoint: Endpoint?) {
        self.endpoint = endpoint
    }
    
    // MARK: Power
    
    func wake() {
        logInfo("requestWake")
        endpoint.sendOneway(PowerCommand.wake)
    }
    
    func sleep() {
        logInfo("requestSleep")
        endpoint.sendOneway(PowerCommand.sleep)
    }

    // MARK: IO
    
    func setMainLED(to color: SyncsColor) {
        logInfo("requestSetMainLED \(color)")
        endpoint.sendOneway(SetMainLEDRequest(color: color))
    }
    
    func setBackLED(to brightness: SyncsBrightness) {
        logInfo("requestSetBackLED \(brightness)")
        endpoint.sendOneway(SetBackLEDRequest(brightness: brightness))
    }
    
    // MARK: Drive
    
    func stopRoll(towards heading: SyncsHeading) {
        logInfo("requestStopRoll")
        endpoint.sendOneway(RollRequest(speed: SyncsSpeed(0), heading: heading, dir: .forward))
    }
    
    // MARK: Sensor
        
    func stopSensorStreaming() {
        logInfo("requestStopSensorStreaming")
        endpoint.sendOneway(StopSensorStreamingRequest())
    }
}
