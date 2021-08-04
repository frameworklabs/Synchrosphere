// Project Synchrosphere
// Copyright 2021, Framework Labs.

import Pappe
import CoreBluetooth

/// Controls the communication with a peripheral; implements the `Endpoint` abstraction.
final class PeripheralController : NSObject, CBPeripheralDelegate, Endpoint, LoggingProviderAccessor {
    
    private let context: ControllerContext
    var peripheral: CBPeripheral! {
        didSet {
            peripheral.delegate = self
        }
    }

    var loggingProvider: SyncsLogging {
        return context
    }

    init(context: ControllerContext) {
        self.context = context
        super.init()
    }

    func makeModule(imports: [Module.Import]) -> Module {
        return Module(imports: imports) { name in
            
            activity (name.DiscoverPeripheralCharacteristics_, []) { val in
                exec {
                    self.context.logInfo("discover services")
                    self.peripheral.discoverServices([.apiService, .antiDosService])
                }
                `await` { self.apiService != nil }
                exec {
                    self.context.logInfo("discover api characteristics")
                    self.peripheral.discoverCharacteristics([.apiCharacteristic], for: self.apiService!)
                }
                `await` { self.apiCharacteristic != nil }
                `if` { self.context.config.deviceSelector.needsTheForce } then: {
                    exec {
                        self.context.logInfo("discover antiDOS characteristics")
                        self.peripheral.discoverCharacteristics([.antiDoSCharacteristic], for: self.antiDOSService!)
                    }
                    `await` { self.antiDOSCharacteristic != nil }
                }
            }
            
            activity (name.UnlockPeripheral_, []) { val in
                `defer` {
                    self.didWrite = false
                    self.didNotify = false
                }
                `if` { self.context.config.deviceSelector.needsTheForce } then: {
                    exec {
                        self.context.logInfo("use the force")
                        self.didWrite = false
                        self.peripheral.writeValue("usetheforce...band".data(using: .ascii)!, for: self.antiDOSCharacteristic!, type: .withResponse)
                    }
                    `await` { self.didWrite }
                }
                exec {
                    self.context.logInfo("enable notify api")
                    self.didNotify = false
                    self.peripheral.setNotifyValue(true, for: self.apiCharacteristic!)
                }
                `await` { self.didNotify }
            }
        }
    }
    
    var endpoint: Endpoint {
        self
    }
    
    private var apiService: CBService? {
        peripheral?.services?.first { $0.uuid == CBUUID.apiService }
    }
    private var antiDOSService: CBService? {
        peripheral?.services?.first { $0.uuid == CBUUID.antiDosService }
    }

    private var apiCharacteristic: CBCharacteristic? {
        apiService?.characteristics?.first { $0.uuid == CBUUID.apiCharacteristic }
    }
    private var antiDOSCharacteristic: CBCharacteristic? {
        antiDOSService?.characteristics?.first { $0.uuid == CBUUID.antiDoSCharacteristic }
    }

    private var didWrite = false
    private var didNotify = false

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        context.trigger()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        context.trigger()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        didWrite = true
        context.trigger()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        didNotify = true
        context.trigger()
    }
    
    private var responses = [RequestID: Response]()
    private var decoder = Decoder()

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }

        decoder.decode(data) { command, sequenceNr, response in
            let id = RequestID(command: command, sequenceNr: sequenceNr)
            self.responses[id] = response
            self.context.trigger()
        }
    }

    private var sequenceNr: UInt8 = 0
    
    func send(_ command: Command, with data: [UInt8], to tid: UInt8) -> RequestID {
        let id = RequestID(command: command, sequenceNr: sequenceNr)
        write(Encoder.encode(command, with: data, tid: tid, sequenceNr: sequenceNr, wantsResponse: true))
        sequenceNr &+= 1
        return id
    }
    
    func sendOneway(_ command: Command, with data: [UInt8], to tid: UInt8) {
        write(Encoder.encode(command, with: data, tid: tid, sequenceNr: sequenceNr, wantsResponse: false))
        sequenceNr &+= 1
    }
    
    func hasResponse(for requestID: RequestID, handler: ResponseHandler?) -> Bool {
        guard let data = responses[requestID] else { return false }
        responses.removeValue(forKey: requestID)
        if let handler = handler {
            handler(data)
        }
        return true
    }
    
    private func write(_ data: Data) {
        guard peripheral.state == .connected else { return }

        var from = 0
        var to = min(20, data.count)
        while true {
            let chunk = data.subdata(in: from..<to)
            peripheral.writeValue(chunk, for: apiCharacteristic!, type: .withoutResponse)
            
            guard data.count > to else { break }
            from = to
            to = min(to + 20, data.count)
        }
    }
}

private extension SyncsDeviceSelector {
    var needsTheForce: Bool {
        switch self {
        case .anyRVR: return false
        case .anyMini: return true
        }
    }
}
