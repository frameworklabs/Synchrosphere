// Project Synchrosphere
// Copyright 2021, Framework Labs.

import Pappe
import Dispatch // for dispatchPrecondition

/// The implementation of the `SyncsControllerContext` protocol.
final class ControllerContext : SyncsControllerContext, LoggingProviderAccessor {
        
    let config: SyncsControllerConfig
    var state: SyncsControllerState = []
    let clock = SyncsClock()
    let requests_: Requests
    var requests: SyncsRequests {
        return requests_
    }
    var processor: Processor!
    
    /// Provides the `SyncsLogging` protocol by delegating to the function optionally defined in the config or printing to stdout otherwise.
    private class LoggingProvider : SyncsLogging {
        private var logger: ((String, SyncsLogLevel) -> Void)!
        private let logLevel: SyncsLogLevel

        init(config: SyncsControllerConfig) {
            logLevel = config.logLevel
            if let logFunction = config.logFunction {
                logger = { [unowned self] msg, level in
                    if isLogEnabled(for: level) {
                        logFunction(msg, level)
                    }
                }
            } else {
                logger = { [unowned self] msg, level in
                    if isLogEnabled(for: level) {
                        print("Syncs [\(level)] \(msg)")
                    }
                }
            }
        }
                
        func log(_ message: String, as level: SyncsLogLevel) {
            logger(message, level)
        }
        
        func isLogEnabled(for level: SyncsLogLevel) -> Bool {
            level >= logLevel
        }
    }
    
    private let loggingProvider_: LoggingProvider
    var loggingProvider: SyncsLogging {
        loggingProvider_
    }

    init(config: SyncsControllerConfig) {
        self.config = config
        loggingProvider_ = LoggingProvider(config: config)
        requests_ = Requests(loggingProvider: loggingProvider_, deviceSelector: config.deviceSelector)
    }
    
    var isTimerRunning = false
    
    func trigger() {
        if config.triggerMode == .timeAndEvents || !isTimerRunning {
            tick()
        }
    }
    
    func tick() {
        dispatchPrecondition(condition: .onQueue(config.queue ?? DispatchQueue.main))
        
        config.willTickCallback?()
        
        try! processor.tick([], [])

        config.didTickCallback?()

        if stateDidChange {
            if isLogEnabled(for: .info) {
                logInfo("state changed " + state.description)
            }
            config.stateDidChangeCallback?(state)
            stateDidChange = false
        }
    }
    
    private var stateDidChange = false
    
    func setState(_ state: SyncsControllerState) {
        if self.state.insert(state).inserted {
            stateDidChange = true
        }
    }
    
    func clearState(_ state: SyncsControllerState) {
        if self.state.remove(state) != nil {
            stateDidChange = true
        }
    }
    
    func hasState(_ state: SyncsControllerState) -> Bool {
        self.state.contains(state)
    }
}

extension SyncsControllerContext {
    func setState(from batteryState: SyncsBatteryState) {
        switch batteryState {
        case .ok:
            clearState(.isBatteryLow)
            clearState(.isBatteryCritical)
        case .low:
            setState(.isBatteryLow)
            clearState(.isBatteryCritical)
        case .critical:
            clearState(.isBatteryLow)
            setState(.isBatteryCritical)
        }
    }
}
