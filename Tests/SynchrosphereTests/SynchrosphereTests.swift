// Project Synchrosphere
// Copyright 2021, Framework Labs.

@testable import Synchrosphere
import Pappe
import XCTest

final class SynchrosphereTests: XCTestCase {
    
    func testEncodeDecode() {
        let inCommand = IOCommand.setLED
        let inPayload: [UInt8] =  [0x00, 0x01, 0xaa]
        let inSeqNr: UInt8 = 42
        let data = Encoder.encode(inCommand, with: inPayload, tid: 1, sequenceNr: inSeqNr, wantsResponse: true)
        
        let decoder = Decoder()
        decoder.decode(data) { outCommand, outSeqNr, result in
            XCTAssertEqual(inCommand, outCommand as! IOCommand)
            XCTAssertEqual(inSeqNr, outSeqNr)
            switch result {
            case .success(let outPayload):
                XCTAssertEqual(Data(inPayload), outPayload)
            default:
                XCTFail()
            }
        }
    }
    
    func testTimers() {
        var config = SyncsControllerConfig(deviceSelector: .anyMini)
        config.tickFrequency = 3
        let context = ControllerContext(config: config)
        let controller = TimerController(context: context)
        context.processor = Module(imports: [controller.makeModule(imports: [])]) { name in
            activity (name.Main, []) { val in
                exec {
                    val.expectedTick = false
                    val.actualTick = false
                }
                cobegin {
                    with {
                        pause
                        pause
                        pause
                        pause
                        exec { val.expectedTick = true }
                        pause
                        
                        exec { val.expectedTick = false }
                        pause
                        pause
                        pause
                        exec { val.expectedTick = true }
                    }
                    with (.weak) {
                        pause // create offset
                        Pappe.run (Syncs.WaitTicks, [3])
                        exec { val.actualTick = true }
                        pause
                        
                        exec { val.actualTick = false }
                        Pappe.run (Syncs.WaitSeconds, [1])
                        exec { val.actualTick = true }
                    }
                    with (.weak) {
                        `repeat` {
                            exec {
                                XCTAssertEqual(val.actualTick as Bool, val.expectedTick)
                            }
                            pause
                        }
                    }
                }
            }
        }.makeProcessor()
        
        for _ in 0..<20 {
            controller.tick()
        }
    }
    
    static var allTests = [
        ("testEncodeDecode", testEncodeDecode),
        ("testTimers", testTimers),
    ]
}
