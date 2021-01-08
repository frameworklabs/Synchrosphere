// Project Synchrosphere
// Copyright 2021, Framework Labs.

/// Allows a type to implement the `SyncsLogging` protocl by forwarding to the `loggingProvider` offered via this  accessor protocol.
protocol LoggingProviderAccessor {
    var loggingProvider: SyncsLogging { get }
}

extension SyncsLogging where Self: LoggingProviderAccessor {
    
    func log(_ message: String, as level: SyncsLogLevel) {
        loggingProvider.log(message, as: level)
    }
    
    func isLogEnabled(for level: SyncsLogLevel) -> Bool {
        return loggingProvider.isLogEnabled(for: level)
    }
}
