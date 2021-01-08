// Project Synchrosphere
// Copyright 2021, Framework Labs.

import Pappe
import Dispatch // for DispatchQueue

/// A way to specify which robot to select when scanning is started.
public enum SyncsDeviceSelector {
    
    /// Selects any Sphero Mini  around. Does *not* prevent a robot to be selected multiple times.
    case anyMini
}

/// Provides information about the progress of a controller and its controlled robot.
public struct SyncsControllerState: OptionSet {
    public let rawValue: Int
    
    /// Public constructor to allow client code to add additional states.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    /// Set when `start` was called on the controller. Cleared when `stop` was called or the main control activity ended.
    public static let isRunning = SyncsControllerState(rawValue: 1 << 0)
    
    /// Set when Bluetooth on the controlling computer is enabled and ready.
    public static let isBluetoothAvailable = SyncsControllerState(rawValue: 1 << 1)
    
    /// Set when a Bluetooth scan for peripherals is in progress.
    public static let isScanning = SyncsControllerState(rawValue: 1 << 2)
    
    /// Set when the selected device was found.
    public static let foundDevice = SyncsControllerState(rawValue: 1 << 3)
    
    /// Set when a connection attempt to the robot is in progress.
    public static let isConnecting = SyncsControllerState(rawValue: 1 << 4)
    
    /// Set when a connection to the robot was established.
    public static let isConnected = SyncsControllerState(rawValue: 1 << 5)
    
    /// Set when Bluetooth service and characteristics introspection is in progress.
    public static let isIntrospecting = SyncsControllerState(rawValue: 1 << 6)
    
    /// Set when the robot woke up from sleep. Cleared when device is put to sleep again.
    public static let isAwake = SyncsControllerState(rawValue: 1 << 7)
    
    /// Asserted when a low battery condition is detected.
    public static let isBatteryLow = SyncsControllerState(rawValue: 1 << 8)
    
    /// Asserted when a criticial battery condition is detected (`isBatteryLow` is cleared in this case).
    public static let isBatteryCritical = SyncsControllerState(rawValue: 1 << 9)
}

extension SyncsControllerState: CustomStringConvertible {
    public var description: String {
        var buf = ""
        func add(_ state: Self, _ msg: String) {
            buf += msg
            buf += contains(state) ? ": 1 " : ": 0 "
        }
        add(.isRunning, "on")
        add(.isBluetoothAvailable, "bt")
        add(.isScanning, "scn")
        add(.foundDevice, "dev")
        add(.isConnecting, "co")
        add(.isConnected, "con")
        add(.isIntrospecting, "int")
        add(.isAwake, "awk")
        add(.isBatteryLow, "low")
        add(.isBatteryCritical, "cri")
        return buf
    }
}

/// A categorization for log messages.
public enum SyncsLogLevel: Comparable {
    
    /// Provides Informative messages about how the robot is commanded.
    case info
    
    /// Communicates error messages.
    case error
}

/// Types adopting this protocol allow its clients to log messages.
public protocol SyncsLogging {
    
    /// Logs the given `message` at the provided `level`.
    ///
    /// - Note: If the message will be actually logged depends on the `logLevel` specified in the config.
    func log(_ message: String, as level: SyncsLogLevel)
    
    /// Returns if logging is enabled for the given `level`.
    func isLogEnabled(for level: SyncsLogLevel) -> Bool
}

public extension SyncsLogging {
    
    /// Logs a `message` of category `.info`.
    func logInfo(_ message: String) {
        log(message, as: .info)
    }

    /// Logs a `message` of category `.error`.
    func logError(_ message: String) {
        log(message, as: .error)
    }
}

/// A collection of data to configure a `SyncsController` to be created.
public struct SyncsControllerConfig {
    
    /// Creates a default config to select the specified device.
    ///
    /// Use the setter methods of this struct to modify the default values of this config.
    public init(deviceSelector: SyncsDeviceSelector = .anyMini) {
        self.deviceSelector = deviceSelector
    }
    
    /// Returns the `SyncsDeviceSelector` as specified in the constructor.
    public let deviceSelector: SyncsDeviceSelector
    
    /// Specifies the minimal log level to be used.
    ///
    /// When set to `info` (which is the default), both `info` as well as `error` messages will be logged.
    /// When set to `error` only `error` messages are logged.
    /// To completely silence log messages, provide a `logFunction` which discards all messages.
    public var logLevel: SyncsLogLevel = .info
    
    /// Assign a function which parameters `message` and `level` to write log messages in a custom way.
    ///
    /// By default, log messages are written out with the `print` command. Assigning a custom function allows you
    /// to write log messages to a mesasge box in an UI or write it to a file. You should respect the `logLevel` config in this case.
    public var logFunction: ((_ message: String, _ level: SyncsLogLevel) -> Void)?

    /// Specifies the frequency of the clock.
    ///
    /// A synchronous program proceeds in steps which are either triggered by events (like a message response from a robot) or by
    /// a timer. This `tickFrequency` specifies how often the timer will trigger  a step within a second. 10Hz is the default value.
    /// The maximum frequency supported by the robot is at 20Hz. To reduce overhead you might want to lower the frequency below 10Hz.
    public var tickFrequency = 10
    
    /// Specifies how often the robot is asked about its current battery state.
    ///
    /// When the battery state is `low` or `critical`, the robot will stop the controllers main activity and get into a mode where it
    /// will blink red constantly. In this case you need to charge the robot and restart the controller.
    ///
    /// Default value results in a check every minute (given a 10Hz `tickFrequency`). If you provide zero, no checks will be performed.
    public var batteryCheckTicks = 600
    
    /// You can provide a callback function which will be called when the state of the controller changes.
    ///
    /// Typically, you assign a callback function to know at least when the controllers main activity has ended.
    public var stateDidChangeCallback: ((SyncsControllerState) -> Void)?
    
    /// Specifies the queue the controller should run on.
    ///
    /// All APIs of a `SyncsController` (including `start` and  `stop` or accessing its `state`) must be called from the
    /// specified queue.  All callbacks from `Synchrosphere` will happen on that queue too.
    /// By default (or when assigning nil) the main queue will be used.
    public var queue: DispatchQueue?
    
    /// Allows you to provide a list of Modules to be used within the `SyncsController` to be created.
    public var imports: [Module] = []
}

/// Allows to detect if a step was due to a fireing timer.
public final class SyncsClock {
    
    /// Returns `true` if the current step was triggered by the timer. `false` if it was triggered by some other event.
    public internal(set) var tick: Bool = false
    
    /// Returns the current tick counter of the clock.
    ///
    /// Can be used in the `tick()` function as a start value.
    public internal(set) var counter: UInt64 = 0
    
    /// Creates a downsampled the clock.
    ///
    /// - Parameter scale: a divider for the clock. A value of e.g. 2 will halve the frequency of the clock.
    /// - Parameter start: the `counter` value from which to start counting for this downsampled clock.
    /// - Returns: `true` if the downsampled clock triggers.
    public func tick(downBy scale: Int, from start: UInt64 = 0) -> Bool {
        return tick && ((counter - start) % UInt64(scale) == 0)
    }
}

/// Provides information about the battery charging state.
public enum SyncsBatteryState : UInt8 {
    case ok = 0x01
    case low = 0x02
    case critical = 0x03
}

/// Type used when specifying the robots main LED  color in the `setMainLED` API.
public struct SyncsColor {
    
    public static let black = SyncsColor()
    public static let white = SyncsColor(red:0xff, green: 0xff, blue: 0xff)
    public static let red = SyncsColor(red:0xff)
    public static let green = SyncsColor(green:0xff)
    public static let blue = SyncsColor(blue:0xff)

    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    
    /// Creates a color with the given rgb values. If omitted, a color channel defaults to 0.
    public init(red: UInt8 = 0, green: UInt8 = 0, blue: UInt8 = 0) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

extension SyncsColor: CustomStringConvertible {
    public var description: String {
        return "r: \(red) g: \(green) b: \(blue)"
    }
}

/// Type used when specifying the robots speed in the `roll` or  `rollForSeconds` APIs.
public typealias SyncsSpeed = UInt8

/// Type used when specifying the robots heading  in the `roll` or  `rollForSeconds` APIs.
public typealias SyncsHeading = UInt16

/// Type used when specifying the robots direction in the `roll` or  `rollForSeconds` APIs.
public enum SyncsDir: UInt8 {
    case forward = 0x00
    case backward = 0x01
}

/// Type used when specifying the robots back LED brightness  in the `setBackLED`API.
public typealias SyncsBrightness = UInt8

/// The set of supported sensors on the robot.
public struct SyncsSensors: OptionSet {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    /// The location sensor providing the `x` and `y` sample values.
    public static let location = SyncsSensors(rawValue: 1 << 0)
    
    /// The velocity sensor providing the `vx` and `vy` sample values.
    public static let velocity = SyncsSensors(rawValue: 1 << 1)

    /// The acceleration sensor providing the `ax` and `ay` sample values.
    public static let acceleration = SyncsSensors(rawValue: 1 << 2)

    /// The heading sensor providing the `yaw` sample value.
    public static let yaw = SyncsSensors(rawValue: 1 << 3)
}

/// The current values of the robots sensors.
///
/// Only the values for the selected sensors are valid.
public struct SyncsSample {
    
    /// The `counter` value of the `SyncsClock` when the sample was created.
    public let timestamp: UInt64
    
    /// The set of selected sensors.
    public let sensors: SyncsSensors
    
    public let x: Float
    public let y: Float
    public let vx: Float
    public let vy: Float
    public let ax: Float
    public let ay: Float
    public let yaw: Float
    
    /// An unset sample for initialization purposes.
    public static let unset = SyncsSample(timestamp: 0, sensors: [], x: 0, y: 0, vx: 0, vy: 0, ax: 0, ay: 0, yaw: 0)
}

extension SyncsSample: CustomStringConvertible {
    public var description: String {
        var result = ""
        if sensors.contains(.location) {
            result += "x: \(x) y: \(y) "
        }
        if sensors.contains(.yaw) {
            result += "yaw: \(yaw) "
        }
        if sensors.contains(.velocity) {
            result += "vx: \(vx) vy: \(vy) "
        }
        if sensors.contains(.acceleration) {
            result += "ax: \(ax) ay: \(ay) "
        }
        return result
    }
}

/// Methods to request a robot to stop some activities in a `defer` construct.
///
/// As it is not possible to run activities in a `defer` construct, the following request methods can be used to stop or reset
/// some robot behavior. These methods will not wait for replies from the robot and should only be used in the `defer` environment.
public protocol SyncsRequests {
        
    // IO

    /// Set the main LED back to the given `color`.
    func setMainLED(to color: SyncsColor)
    
    /// Set the brightness of the back LED.
    func setBackLED(to brightness: SyncsBrightness)

    // Drive
    
    /// Bring the robot to a stop maintaining the given `heading`.
    func stopRoll(towards heading: SyncsHeading)
}

/// Provides access to information - like the initial config - to  the activities of a controller.
public protocol SyncsControllerContext: SyncsLogging {
    
    /// Access to the inital config used on construction of the controller.
    var config: SyncsControllerConfig { get }
    
    /// Access to the current state of the controller.
    var state: SyncsControllerState { get }

    /// Asserts the given `state`.
    func setState(_ state: SyncsControllerState)
    
    /// Un-asserts the given `state`.
    func clearState(_ state: SyncsControllerState)
    
    // Returns whether the given `state` is currently asserted or not.
    func hasState(_ state: SyncsControllerState) -> Bool

    /// Access to the clock associated with the controller.
    var clock: SyncsClock { get }

    /// Triggers a step of the synchronous control program.
    ///
    /// - Note: There should be no need to manually trigger a step from normal client code.
    func tick()
    
    /// Provides the API to send requests to the sphero robot.
    var requests: SyncsRequests { get }
}

/// The representation and handle for a robot controller created via `makeController`.
public protocol SyncsController {
    
    /// The context associated with this controller providing access to data like its state as well as the robots API.
    var context: SyncsControllerContext { get }
    
    /// Needs to be called on a created controller to start the discovery, connection and controlling process.
    func start()
    
    /// Can be called on a started controller to stop it at any time.
    ///
    /// Normally, the controller stops automatically when the main activity ends. Calling `stop` explicitly allows
    /// to stop a lengthy scanning attempt or bring the robot to an emergeny stop.
    /// Regardless of  an automatic or manual stop, the robot motor is turned off and the robot put to sleep.
    func stop()
}

/// The factory to create robot controllers.
///
/// This is the main entrypoint into the Synchrosphere APIs. Call `makeController` to create a controller for the given config and
/// activity builder. Then call `start`on the returned controller to begin robot oerpations.
public final class SyncsEngine {
    
    /// Creates an engine instance.
    ///
    /// Currently an engine does not contain state but might so in the future. Best create and hold onto a single instance in your app.
    public init() {
    }

    /// Creates a robot controller with the given ` config` and activity `builder`.
    ///
    /// Call this method to create a new controller for a Sphero robot with control code provided as synchronous
    /// [Pappe](https://github.com/frameworklabs/Pappe) activities.
    ///
    /// One of the provided activities needs to be named "Main" and will be called without any arguments when - after calling `start` on
    /// the returned controller -  a robot conforming to `config` was scanned, connected and woken up. When control returns from this
    /// "Main" activity, the robot will be stopped, put to sleep and disconnected again.
    ///
    /// Example:
    /// ```
    /// let config = SyncsControllerConfig(deviceSelector: .anyMini)
    /// controller = engine.makeController(for: config) { name, context in
    ///   activity (name.Main, []) { val in
    ///     run (Syncs.SetMainLED, [SyncsColor.red])
    ///     run (Syncs.WaitSeconds, [1])
    ///     run (Syncs.SetMainLED, [SyncsColor.green])
    ///     run (Syncs.WaitSeconds, [1])
    ///   }
    /// }
    /// controller.start()
    /// ```
    /// This creates a controller - for some Sphero Mini around - which sets its main LED to red and then after a second to green before
    /// giving up control after another second.
    ///
    /// - Parameter config:  configuration information for the controller to be created.
    /// - Parameter builder: a closure to create a list of `Activity` objects (one of which must be named "Main").
    /// - Parameter names:   an object which supports @dynamicMemberLookup to use dot notation instead of quotation marks.
    /// - Parameter context: a `SyncsControllerContext` which provides access to objects like the intial `config`,
    ///                      logging and the clock.
    /// - Returns: a `SyncsController` instance used to start and stop the robot control. Keep this alive (e.g. by assigning it to
    ///            an instance variable) for as long as you want to control the robot.
    public func makeController(for config: SyncsControllerConfig = SyncsControllerConfig(), @ActivityBuilder code builder: (_ names: ID, _ context: SyncsControllerContext) -> [Activity]) -> SyncsController {
        MainController(config: config, builder: builder)
    }
}

/// Namespace for the names of the activities provided by Syncrhrosphere.
public struct Syncs {

    // Clock
    
    /// Activity to pause the current trail for a given number of ticks.
    ///
    /// The time the trail waits depends on the `tickFrequency` specified in the config.
    ///
    /// `activity WaitTicks (ticks: Int)`
    ///
    /// - Parameters ticks: number of clock ticks to wait.
    public static let WaitTicks = "SyncsWaitTicks"

    /// Activity to pause the current trail for the given number of milliseconds.
    ///
    /// `activity WaitMilliseconds (milliseconds: Int)`
    ///
    /// - Parameters milliseconds: number of milliseconds to wait.
    public static let WaitMilliseconds = "SyncsWaitMilliseconds"

    /// Activity to pause the current trail for the given number of seconds.
    ///
    /// `activity WaitSeconds (seconds: Int)`
    ///
    /// - Parameters seconds: number of seconds to wait.
    public static let WaitSeconds = "SyncsWaitSeconds"

    // Power

    /// Activity to query the current battery state.
    ///
    /// `activity GetBatteryState () -> SyncsBatteryState?`
    ///
    /// - Returns  if successful the current `SyncsBatteryState` - nil otherwise.
    public static let GetBatteryState = "SyncsGetBatteryState"

    // IO
    
    /// Activity to set the main LED of the robot to a given color.
    ///
    /// `activity SetMainLED (color: SyncsColor)`
    ///
    /// - Parameter color: a `SyncsColor` value.
    public static let SetMainLED = "SyncsSetMainLED"

    /// Activity to set the brightness of the back LED of the robot.
    ///
    /// `activity SetBackLED (brightness: SyncsBrightness)`
    ///
    /// - Parameter brightness: a `SyncsBrightness` value.
    public static let SetBackLED = "SyncsSetBackLED"
    
    // Drive

    /// Activity to reset the yaw to opposite direction where the back LED would currently shine.
    ///
    /// `activity ResetHeading ()`
    public static let ResetHeading = "SyncsResetHeading"
    
    /// Activity to trigger the robot to roll with a given speed and heading.
    ///
    /// This activity requests a roll and returns while the robot will roll for 2 seconds if not commanded otherwise thereafter.
    /// Use `RollForSeconds` instead to have an activity which lasts as long as the robot rolls.
    ///
    /// `activity Roll (speed: SyncsSpeed, heading: SyncsHeading, dir: SyncsDir)`
    ///
    /// - Parameter speed: the speed the robot should reach when rolling.
    /// - Parameter heading: the heading to roll towards in degrees from 0 to 360.
    /// - Parameter dir: the direction to roll - either `forward` or `backward`.
    public static let Roll = "SyncsRoll"

    /// Activity to roll the robot with a given speed and heading for a specified number of seconds.
    ///
    /// After the given time to roll, the robot will be requested to stop rolling.
    ///
    /// `activity RollForSeconds (speed: SyncsSpeed, heading: SyncsHeading, dir: SyncsDir, seconds: Int)`
    ///
    /// - Parameter speed: the speed the robot should reach when rolling.
    /// - Parameter heading: the heading to roll towards in degrees from 0 to 360.
    /// - Parameter dir: the direction to roll - either `forward` or `backward`.
    /// - Parameter seconds: the number of seconds to roll before it stops.
    public static let RollForSeconds = "SyncsRollForSeconds"
    
    /// Activity to bring robot to a stop.
    ///
    /// `activity StopRoll (heading: SyncsHeading)`
    ///
    /// - Parameter heading: the heading to keep while slowing down and when being stopped.
    public static let StopRoll = "SyncsStopRoll"
    
    // Sensor
    
    /// Activity to reset the locator.
    ///
    /// The current position will be set as (0, 0) by this call.
    ///
    /// `activity ResetLocator ()`
    public static let ResetLocator = "SyncsResetLocator"
    
    /// Activty to stream sensor data from the robot.
    ///
    /// `activity SensorStreamer (frequency: Int, sensors: SyncsSensors) (sample: SyncsSample)`
    ///
    /// - Parameter frequency: the frequency at which to stream data from the robot. Best to be aligned with `tickFrequency`.
    /// - Parameter sensors: the set of sensors selected to stream data.
    /// - Parameter sample: contains the current value for all selected sensors - updated at the specified `frequency`.
    public static let SensorStreamer = "SyncsSensorStreamer"
}
