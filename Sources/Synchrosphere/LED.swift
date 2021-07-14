// Project Synchrosphere
// Copyright 2021, Framework Labs.

/// All RVR LEDs.
enum LED : UInt32, CaseIterable {
    
    case headlightRightR        = 0x0000_0001
    case headlightRightG        = 0x0000_0002
    case headlightRightB        = 0x0000_0004
    
    case headlightLeftR         = 0x0000_0008
    case headlightLeftG         = 0x0000_0010
    case headlightLeftB         = 0x0000_0020

    case statusIndicationLeftR  = 0x0000_0040
    case statusIndicationLeftG  = 0x0000_0080
    case statusIndicationLeftB  = 0x0000_0100

    case statusIndicationRightR = 0x0000_0200
    case statusIndicationRightG = 0x0000_0400
    case statusIndicationRightB = 0x0000_0800

    case batteryDoorRearR       = 0x0000_1000
    case batteryDoorRearG       = 0x0000_2000
    case batteryDoorRearB       = 0x0000_4000

    case batteryDoorFrontR      = 0x0000_8000
    case batteryDoorFrontG      = 0x0001_0000
    case batteryDoorFrontB      = 0x0002_0000

    case powerButtonFrontR      = 0x0004_0000
    case powerButtonFrontG      = 0x0008_0000
    case powerButtonFrontB      = 0x0010_0000

    case powerButtonRearR       = 0x0020_0000
    case powerButtonRearG       = 0x0040_0000
    case powerButtonRearB       = 0x0080_0000

    case breaklightLeftR        = 0x0100_0000
    case breaklightLeftG        = 0x0200_0000
    case breaklightLeftB        = 0x0400_0000

    case breaklightRightR       = 0x0800_0000
    case breaklightRightG       = 0x1000_0000
    case breaklightRightB       = 0x2000_0000
}

private typealias LEDRGBList = [(LED, LED, LED)]

private extension SyncsRVRLEDs {
    var rbgLEDs: LEDRGBList {
        var res = LEDRGBList()
        if contains(.batteryDoorFront) {
            res.append((LED.batteryDoorFrontR, LED.batteryDoorFrontG, LED.batteryDoorFrontB))
        }
        if contains(.batteryDoorRear) {
            res.append((LED.batteryDoorRearR, LED.batteryDoorRearG, LED.batteryDoorRearB))
        }
        if contains(.breaklightLeft) {
            res.append((LED.breaklightLeftR, LED.breaklightLeftG, LED.breaklightLeftB))
        }
        if contains(.breaklightRight) {
            res.append((LED.breaklightRightR, LED.breaklightRightG, LED.breaklightRightB))
        }
        if contains(.headlightLeft) {
            res.append((LED.headlightLeftR, LED.headlightLeftG, LED.headlightLeftB))
        }
        if contains(.headlightRight) {
            res.append((LED.headlightRightR, LED.headlightRightG, LED.headlightRightB))
        }
        if contains(.powerButtonFront) {
            res.append((LED.powerButtonFrontR, LED.powerButtonFrontG, LED.powerButtonFrontB))
        }
        if contains(.powerButtonRear) {
            res.append((LED.powerButtonRearR, LED.powerButtonRearG, LED.powerButtonRearB))
        }
        if contains(.statusIndicationLeft) {
            res.append((LED.statusIndicationLeftR, LED.statusIndicationLeftG, LED.statusIndicationLeftB))
        }
        if contains(.statusIndicationRight) {
            res.append((LED.statusIndicationRightR, LED.statusIndicationRightG, LED.statusIndicationRightB))
        }
        return res
    }
}

private extension SyncsColor {
    func apply(to rgb: (LED, LED, LED)) -> [LED: SyncsBrightness] {
        [rgb.0: red, rgb.1: green, rgb.2: blue]
    }
}

func ledColorsToBrightness(_ mapping: [SyncsRVRLEDs: SyncsColor]) -> (UInt32, [SyncsBrightness]) {
    var ledMapping = [LED: SyncsBrightness]()
    for (rvrLED, color) in mapping {
        let ledRGBList = rvrLED.rbgLEDs
        for ledRGB in ledRGBList {
            ledMapping.merge(color.apply(to: ledRGB), uniquingKeysWith: max)
        }
    }
    return ledMappingToBrightness(ledMapping)
}

private func ledMappingToBrightness(_ mapping: [LED: SyncsBrightness]) -> (UInt32, [SyncsBrightness]) {
    var mask: UInt32 = 0
    var brightness: [SyncsBrightness] = []

    for led in LED.allCases {
        if let value = mapping[led] {
            mask |= led.rawValue
            brightness.append(value)
        }
    }
    return (mask, brightness)
}
