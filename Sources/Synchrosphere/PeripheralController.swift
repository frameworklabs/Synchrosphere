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
                    self.peripheral.discoverServices(nil)
                }
                await { self.peripheral.services != nil }
                exec {
                    self.context.logInfo("discover characteristics")
                    guard let services = self.peripheral.services else { return }
                    for service in services {
                        self.peripheral.discoverCharacteristics(nil, for: service)
                    }
                }
                await { self.didDiscoverCharacteristics }
            }
            
            activity (name.UnlockPeripheral_, []) { val in
                `defer` {
                    self.didWrite = false
                    self.didNotify = false
                }
                exec {
                    self.context.logInfo("use the force")
                    self.didWrite = false
                    self.peripheral.writeValue("usetheforce...band".data(using: .ascii)!, for: self.antiDOSCharacteristic, type: CBCharacteristicWriteType.withResponse)
                }
                await { self.didWrite }
                exec {
                    self.context.logInfo("enable notify api")
                    self.didNotify = false
                    self.peripheral.setNotifyValue(true, for: self.apiCharacteristic)
                }
                await { self.didNotify }
            }
        }
    }
    
    var endpoint: Endpoint {
        self
    }
    
    private var antiDOSCharacteristic: CBCharacteristic!
    private var apiCharacteristic: CBCharacteristic!

    private var didDiscoverCharacteristics: Bool {
        guard let p = peripheral, let ss = p.services else {
            return false
        }
        for s in ss {
            guard let cs = s.characteristics else {
                return false
            }
            for c in cs {
                if c.uuid == .antiDoSCharacteristic {
                    antiDOSCharacteristic = c
                } else if c.uuid == .apiCharacteristic {
                    apiCharacteristic = c
                }
            }
        }
        return true
    }
    
    private var didWrite = false
    private var didNotify = false

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        context.tick()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        context.tick()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        didWrite = true
        context.tick()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        didNotify = true
        context.tick()
    }
    
    private var responses = [RequestID: Response]()
    private var decoder = Decoder()

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }

        decoder.decode(data) { command, sequenceNr, response in
            let id = RequestID(command: command, sequenceNr: sequenceNr)
            self.responses[id] = response
            self.context.tick()
        }
    }

    private var sequenceNr: UInt8 = 0
    
    func send(_ command: Command, with data: [UInt8]) -> RequestID {
        let id = RequestID(command: command, sequenceNr: sequenceNr)
        if peripheral.state == .connected {
            peripheral.writeValue(Encoder.encode(command, with: data, sequenceNr: sequenceNr, wantsResponse: true), for: apiCharacteristic, type: .withResponse)
        }
        sequenceNr &+= 1
        return id
    }
    
    func sendOneway(_ command: Command, with data: [UInt8]) {
        if peripheral.state == .connected {
            peripheral.writeValue(Encoder.encode(command, with: data, sequenceNr: sequenceNr, wantsResponse: false), for: apiCharacteristic, type: .withResponse)
        }
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
}
