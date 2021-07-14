// Project Synchrosphere
// Copyright 2021, Framework Labs.

import Foundation // for Data

// MARK: - Endpoint helper types

/// The different functional categories within a spehro robot.
enum Device : UInt8 {
    case power = 0x13
    case io = 0x1a
    case drive = 0x16
    case sensor = 0x18
}

/// The common type for the different command enums.
protocol Command {
    var rawValue: UInt8 { get }
    var device: Device { get }
}

/// The commands possible on the power device.
enum PowerCommand : UInt8, Command {
    case sleep = 0x01
    case wake = 0x0D
    case getBatteryState = 0x17

    var device: Device {
        .power
    }
}

/// The commands possible on the io device.
enum IOCommand : UInt8, Command {
    case setLED = 0x0e
    case setAllLEDs = 0x1a

    var device: Device {
        return .io
    }
}

/// The commands possible on the drive device.
enum DriveCommand : UInt8, Command {
    case resetHeading = 0x06
    case roll = 0x07

    var device: Device {
        return .drive
    }
}

/// The commands possible on the sensor device.
enum SensorCommand : UInt8, Command {
    case setStreaming = 0x00
    case resetLocator = 0x13
    case setLocatorFlags = 0x17
    case notifySensorData = 0x02
    case configureStreamingService = 0x39
    case startStreamingService = 0x3A
    case stopStreamingService = 0x3B
    case clearStreamingService = 0x3C
    case streamingServiceDataNotify = 0x3D

    var device: Device {
        return .sensor
    }
}

extension Device {
    func makeCommand(commandID: UInt8) -> Command? {
        switch self {
        case .power:
            return PowerCommand(rawValue: commandID)
        case .io:
            return IOCommand(rawValue: commandID)
        case .drive:
            return DriveCommand(rawValue: commandID)
        case .sensor:
            return SensorCommand(rawValue: commandID)
        }
    }
}

/// The possible errors reported from a robot on a wrong request.
enum RequestError : UInt8, Swift.Error {
    case success = 0x00
    case badDeviceID = 0x01
    case badCommandID = 0x02
    case notYetImplemented = 0x03
    case restricted = 0x04
    case badDataLength = 0x05
    case commandFailed = 0x06
    case badParameterValue = 0x07
    case busy = 0x08
    case badTargetID = 0x09
    case targetUnavailable = 0x0A
}

/// The response to a request is either a data payload or an error of type `RequestError`.
typealias Response = Result<Data, RequestError>

/// A function type which takes a `Response` to handle.
typealias ResponseHandler = (Response) -> Void

/// Identifies a request made to the robot; used to correlate responses with requests.
struct RequestID : Hashable {
    let command: Command
    let sequenceNr: UInt8

    static func == (lhs: RequestID, rhs: RequestID) -> Bool {
        return lhs.command.rawValue == rhs.command.rawValue && lhs.command.device == rhs.command.device && lhs.sequenceNr == rhs.sequenceNr
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(command.rawValue)
        hasher.combine(command.device.rawValue)
        hasher.combine(sequenceNr)
    }
}

// MARK: - Endpoint type

/// An abstraction to communicate with a robot.
protocol Endpoint : SyncsLogging {
    func send(_ command: Command, with data: [UInt8], to tid: UInt8) -> RequestID
    func sendOneway(_ command: Command, with data: [UInt8], to tid: UInt8)
    func hasResponse(for requestID: RequestID, handler: ResponseHandler?) -> Bool
}

extension Endpoint {
    func send(_ command: Command, to tid: UInt8) -> RequestID {
        send(command, with: [], to: tid)
    }

    func sendOneway(_ command: Command, to tid: UInt8) {
        sendOneway(command, with: [], to: tid)
    }

    func hasResponse(for requestID: RequestID) -> Bool {
        hasResponse(for: requestID) { response in
            if case .failure(let error) = response {
                log("Request: \(requestID) failed with: \(error)", as: .error)
            }
        }
    }
}

// MARK: - Request and Response formatters/parsers

/// An abstraction which  provides both the command and data needed to send a request with arguments.
protocol Request {
    var command: Command { get }
    var data: [UInt8] { get }
    var tid: UInt8 { get }
}

extension Endpoint {
    func send(_ request: Request) -> RequestID {
        send(request.command, with: request.data, to: request.tid)
    }
    
    func sendOneway(_ request: Request) {
        sendOneway(request.command, with: request.data, to: request.tid)
    }
}

/// Errors thrown when parsing a `Response` fails.
enum ParseError : Error {
    case wrongPayloadSize
    case unknownValue
    case unexpectedToken
}

/// Tries to parse a `Response` into a `SyncsBatteryState`.
func parseGetBatteryStateResponse(_ response: Response) throws -> SyncsBatteryState {
    let data = try response.get()
    guard data.count == 1 else { throw ParseError.wrongPayloadSize }
    guard let state = SyncsBatteryState(rawValue: data[0]) else { throw ParseError.unknownValue }
    return state
}

/// Encapsulates command and data needed to issue a set main led color request.
struct SetMainLEDRequest : Request {
    let command: Command = IOCommand.setLED
    let data: [UInt8]
    let tid: UInt8 = 1
    
    init(color: SyncsColor) {
        data = [0x00, 0x0e, color.red, color.green, color.blue]
    }
}

/// Encapsulates command and data needed to issue a set back led brightness request.
struct SetBackLEDRequest : Request {
    let command: Command = IOCommand.setLED
    let data: [UInt8]
    let tid: UInt8 = 1

    init(brightness: SyncsBrightness) {
        data = [0x00, 0x01, brightness]
    }
}

struct SetAllLEDsRequest : Request {
    let command: Command = IOCommand.setAllLEDs
    let data: [UInt8]
    let tid: UInt8 = 1

    init(mask: UInt32, brightness: [SyncsBrightness]) {
        data = Encoder.encodeUInt32(mask) + brightness
    }
    
    init(mapping: [SyncsRVRLEDs: SyncsColor]) {
        let (mask, brightness) = ledColorsToBrightness(mapping)
        self.init(mask:mask, brightness: brightness)
    }
}

/// Encapsulates command and data needed to issue a roll request.
struct RollRequest : Request {
    let command: Command = DriveCommand.roll
    let data: [UInt8]
    let tid: UInt8 = 2

    init(speed: SyncsSpeed, heading: SyncsHeading, dir: SyncsDir) {
        let headingBytes = Encoder.encodeUInt16(heading)
        data = [speed, headingBytes[0], headingBytes[1], dir.rawValue]
    }
}

private extension SyncsSensors {
    var mask: UInt32 {
        var res: UInt32 = 0
        if contains(.location) {
            res |= 0x60
        }
        if contains(.velocity) {
            res |= 0x18
        }
        if contains(.acceleration) {
            res |= 0xC000
        }
        if contains(.yaw) {
            res |= 0x10000
        }
        return res
    }
}

/// The sequence number used for streaming data notifications.
let sensorDataSequenceNr: UInt8 = 0xff

/// Tries to parse a `Response` into a `SyncsSample`.
func parseStreamedSampleResponse(_ response: Response, timestamp: UInt64, sensors: SyncsSensors) throws -> SyncsSample {
    let data = try response.get()
    
    var index = 0
    func nextIndex() -> Int {
        let res = index
        index += 4
        return res
    }
    func checkHasBytes(_ n: Int) throws {
        guard data.count >= index + n else { throw ParseError.wrongPayloadSize }
    }
    
    var yaw: Float = 0
    var ax: Float = 0
    var ay: Float = 0
    var x: Float = 0
    var y: Float = 0
    var vx: Float = 0
    var vy: Float = 0
    
    if sensors.contains(.yaw) {
        try checkHasBytes(4)
        yaw = Decoder.decodeFloat(data, at: nextIndex())
    }
    if sensors.contains(.acceleration) {
        try checkHasBytes(8)
        ax = Decoder.decodeFloat(data, at: nextIndex())
        ay = Decoder.decodeFloat(data, at: nextIndex())
    }
    if sensors.contains(.location) {
        try checkHasBytes(8)
        x = Decoder.decodeFloat(data, at: nextIndex())
        y = Decoder.decodeFloat(data, at: nextIndex())
    }
    if sensors.contains(.velocity) {
        try checkHasBytes(8)
        vx = Decoder.decodeFloat(data, at: nextIndex())
        vy = Decoder.decodeFloat(data, at: nextIndex())
    }

    return SyncsSample(timestamp: timestamp, sensors: sensors, x: x, y: y, vx: vx, vy: vy, ax: ax, ay: ay, yaw: yaw)
}

/// Encapsulates command and data needed to issue a start streaming request.
struct StartSensorStreamingRequest : Request {
    let command: Command = SensorCommand.setStreaming
    let data: [UInt8]
    let tid: UInt8 = 2

    init(period: UInt16, sensors: SyncsSensors) {
        let periodBytes = Encoder.encodeUInt16(period)
        let maskBytes = Encoder.encodeUInt32(sensors.mask)
        data = periodBytes + [0] + maskBytes
    }
}

/// Encapsulates command and data needed to issue a stop streaming request.
struct StopSensorStreamingRequest : Request {
    let command: Command = SensorCommand.setStreaming
    let data: [UInt8] = [0x00, 0x00, 0, 0x00, 0x00, 0x00, 0x00]
    let tid: UInt8 = 2
}

struct ConfigureStreamingServiceRequest : Request {
    let command: Command = SensorCommand.configureStreamingService
    let data: [UInt8]
    let tid: UInt8 = 2
    
    init(sensors: SyncsSensors) {
        var data: [UInt8] = [0x01]
        if sensors.contains(.yaw) {
            data +=  [0x00, 0x01, 0x02]
        }
        if sensors.contains(.acceleration) {
            data +=  [0x00, 0x02, 0x02]
        }
        if sensors.contains(.location) {
            data +=  [0x00, 0x06, 0x02]
        }
        if sensors.contains(.velocity) {
            data +=  [0x00, 0x07, 0x02]
        }
        self.data = data
    }
}

struct StartStreamingServiceRequest : Request {
    let command: Command = SensorCommand.startStreamingService
    let data: [UInt8]
    let tid: UInt8 = 2
    
    init(period: UInt16) {
        data = Encoder.encodeUInt16(period)
    }
}

func parseStreamingServiceDataNotifyResponse(_ response: Response, timestamp: UInt64, sensors: SyncsSensors) throws -> SyncsSample {
    let data = try response.get()

    if data[0] != 0x01 {
        throw ParseError.unexpectedToken
    }
    
    var index = 1
    func nextIndex() -> Int {
        let res = index
        index += 4
        return res
    }
    func checkHasBytes(_ n: Int) throws {
        guard data.count >= index + n else { throw ParseError.wrongPayloadSize }
    }
    
    var yaw: Float = 0
    var ax: Float = 0
    var ay: Float = 0
    var x: Float = 0
    var y: Float = 0
    var vx: Float = 0
    var vy: Float = 0
    
    if sensors.contains(.yaw) {
        try checkHasBytes(12)        
        _ = nextIndex() // pitch
        _ = nextIndex() // roll
        yaw = normalize(Decoder.decodeUInt32(data, at: nextIndex()), -180.0, 180.0)
    }
    if sensors.contains(.acceleration) {
        try checkHasBytes(8)
        ax = normalize(Decoder.decodeUInt32(data, at: nextIndex()), -16.0, 16.0)
        ay = normalize(Decoder.decodeUInt32(data, at: nextIndex()), -16.0, 16.0)
        _ = nextIndex() // az
    }
    if sensors.contains(.location) {
        try checkHasBytes(8)
        x = normalize(Decoder.decodeUInt32(data, at: nextIndex()), -16000.0, 16000.0)
        y = normalize(Decoder.decodeUInt32(data, at: nextIndex()), -16000.0, 16000.0)
    }
    if sensors.contains(.velocity) {
        try checkHasBytes(8)
        vx = normalize(Decoder.decodeUInt32(data, at: nextIndex()), -5.0, 5.0)
        vy = normalize(Decoder.decodeUInt32(data, at: nextIndex()), -5.0, 5.0)
    }

    return SyncsSample(timestamp: timestamp, sensors: sensors, x: x, y: y, vx: vx, vy: vy, ax: ax, ay: ay, yaw: yaw)
}

private func normalize(_ val: UInt32, _ newMin: Float, _ newMax: Float) -> Float {
    return (Float(val) / Float(UInt32.max)) * (newMax - newMin) + newMin
}

// MARK: - Encoding/Decoding

/// Names for the escaping encoding scheme.
private enum Encoding : UInt8 {
    case ESC = 0xAB
    case SOP = 0x8D
    case EOP = 0xD8
    case ESC_ESC = 0x23
    case ESC_SOP = 0x05
    case ESC_EOP = 0x50
}

private extension Data {
    mutating func append(_ encoding: Encoding) {
        append(encoding.rawValue)
    }
}

/// Flags used in the Data Protocol.
private struct Flags : OptionSet {
    let rawValue: UInt8

    static let isResponse = Flags(rawValue: 0b0000_0001)
    static let requestResponse = Flags(rawValue: 0b0000_0010)
    static let requestOnlyErrorResponse = Flags(rawValue: 0b0000_0100)
    static let packetIsActivity = Flags(rawValue: 0b0000_1000)
    static let packetHasTID = Flags(rawValue: 0b0001_0000)
    static let packetHasSID = Flags(rawValue: 0b0010_0000)
}

private enum FrameElement: Int {
    case did = 0
    case cid
    case seq
    case err
    case data
}

private struct FrameElementIndices {
    private let indices: [Int]
    
    init(flags: Flags) {
        let tidOffset = flags.contains(.packetHasTID) ? 1 : 0
        let sidOffset = flags.contains(.packetHasSID) ? 1 : 0
        let errOffset = flags.contains(.isResponse) ? 1 : 0
        indices = [
            1 + tidOffset + sidOffset,
            2 + tidOffset + sidOffset,
            3 + tidOffset + sidOffset,
            4 + tidOffset + sidOffset,
            4 + tidOffset + sidOffset + errOffset
        ]
    }
    
    subscript(element: FrameElement) -> Int {
        indices[element.rawValue]
    }
}

/// A namespace for methods which encode requests into a byte-sequence to be sent to a robot.
struct Encoder {
    static func encode(_ command: Command, with payload: [UInt8], tid: UInt8, sequenceNr: UInt8, wantsResponse: Bool) -> Data {
        var data = Data(capacity: 0x20)

        var flags: Flags = [.packetIsActivity, .packetHasTID]
        if wantsResponse {
            flags.formUnion(.requestResponse)
        }
        data.append(flags.rawValue)
        data.append(tid)
        data.append(command.device.rawValue)
        data.append(command.rawValue)
        data.append(sequenceNr)
        data.append(contentsOf: payload)

        var checksum: UInt8 = 0
        for byte in data {
            checksum = checksum &+ byte
        }
        checksum = ~checksum

        data.append(checksum)
        
        var result = Data(capacity: 0x20)
        result.append(.SOP)
        for c in data {
            switch c {
            case Encoding.ESC.rawValue:
                result.append(.ESC)
                result.append(.ESC_ESC)
            case Encoding.SOP.rawValue:
                result.append(.ESC)
                result.append(.ESC_SOP)
            case Encoding.EOP.rawValue:
                result.append(.ESC)
                result.append(.ESC_EOP)
            default:
                result.append(c)
            }
        }
        result.append(.EOP)
        
        return result
    }
    
    static func encodeUInt16(_ val: UInt16) -> [UInt8] {
        let high: UInt16 = (val >> 8) & 0xff
        let low: UInt16 = val & 0xff
        return [UInt8(high), UInt8(low)]
    }
    
    static func encodeUInt32(_ val: UInt32) -> [UInt8] {
        let b0: UInt32 = (val >> 24) & 0xff
        let b1: UInt32 = (val >> 16) & 0xff
        let b2: UInt32 = (val >> 8) & 0xff
        let b3: UInt32 = val & 0xff
        return [UInt8(b0), UInt8(b1), UInt8(b2), UInt8(b3)]
    }

    static func encodeBool(_ val: Bool) -> [UInt8] {
        [val ? 1 : 0]
    }
}

/// A class to decode  a byte-sequence sent from the robot into command and payload.
final class Decoder {
    private var buf: Data!
    
    func decode(_ data: Data, handler: ((_ cmd: Command, _ seq: UInt8, _ result: Response) -> Void)) {
        for ch in data {
            switch ch {
            case Encoding.SOP.rawValue:
                buf = Data(capacity: 0x20)
            case Encoding.EOP.rawValue:
                var data = Data(capacity: buf.count)
                var isEscaping = false
                for c in buf {
                    if isEscaping {
                        switch (c) {
                        case Encoding.ESC_ESC.rawValue:
                            data.append(.ESC)
                        case Encoding.ESC_SOP.rawValue:
                            data.append(.SOP)
                        case Encoding.ESC_EOP.rawValue:
                            data.append(.EOP)
                        default:
                            assertionFailure()
                        }
                        isEscaping = false
                    } else {
                        if c == Encoding.ESC.rawValue {
                            isEscaping = true
                        } else {
                            data.append(c)
                        }
                    }
                }
                
                let result: Response
                let flags = Flags(rawValue: data[0])
                let indices = FrameElementIndices(flags: flags)
                if flags.contains(.isResponse) {
                    if data[indices[.err]] != 0x00 {
                        result = .failure(RequestError(rawValue: data[indices[.err]])!)
                    } else {
                        result = .success(data.subdata(in: indices[.data]..<data.count - 1))
                    }
                } else {
                    result = .success(data.subdata(in: indices[.data]..<data.count - 1))
                }
                guard let device = Device(rawValue: data[indices[.did]]) else { return }
                guard let command = device.makeCommand(commandID: data[indices[.cid]]) else { return }
                handler(command, data[indices[.seq]], result)
            default:
                buf.append(ch)
            }
        }
    }
    
    static func decodeFloat(_ data: Data, at pos: Int) -> Float {
        return Float32(bitPattern: decodeUInt32(data, at: pos))
    }

    static func decodeUInt16(_ data: Data, at pos: Int) -> UInt16 {
        UInt16(data[pos]) << 8 + UInt16(data[pos + 1])
    }
    
    static func decodeUInt32(_ data: Data, at pos: Int) -> UInt32 {
        var acc: UInt32 = 0x00
        acc |= UInt32(data[pos + 0]) << 24
        acc |= UInt32(data[pos + 1]) << 16
        acc |= UInt32(data[pos + 2]) << 8
        acc |= UInt32(data[pos + 3])
        return acc
    }
}
