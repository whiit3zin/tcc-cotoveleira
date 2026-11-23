import Foundation

struct DiagnosticTelemetry: Equatable {
    enum DetectionState: UInt8 {
        case waitingForExtension, waitingForFlexion, waitingForReturn, reset
    }

    struct FlexSignal: Equatable {
        let rawADC: UInt16
        let filteredADC: UInt16
        let extensionADC: UInt16
        let flexionADC: UInt16
        let deadZoneADC: UInt8
    }

    struct IMUHealth: OptionSet {
        let rawValue: UInt8
        static let detected = Self(rawValue: 1 << 0)
        static let orientationValid = Self(rawValue: 1 << 1)
        static let i2cError = Self(rawValue: 1 << 2)

        var hasUsableOrientation: Bool {
            contains([.detected, .orientationValid]) && !contains(.i2cError)
        }
    }

    struct IMUSignal: Equatable {
        let rawCentidegrees: Int16
        let filteredCentidegrees: Int16
        let extensionCentidegrees: Int16
        let flexionCentidegrees: Int16
        let health: IMUHealth

        var rawDegrees: Double { Double(rawCentidegrees) / 100 }
        var filteredDegrees: Double { Double(filteredCentidegrees) / 100 }
        var extensionDegrees: Double { Double(extensionCentidegrees) / 100 }
        var flexionDegrees: Double { Double(flexionCentidegrees) / 100 }
    }

    enum Signal: Equatable {
        case flex(FlexSignal)
        case imu(IMUSignal)
    }

    let signal: Signal
    let progressPercent: UInt8
    let detectionState: DetectionState
    let calibrationValid: Bool
    let batteryMillivolts: UInt16
    let extensionThresholdPercent: UInt8
    let flexionThresholdPercent: UInt8
    let emaPercent: UInt8

    var version: UInt8 {
        switch signal {
        case .flex: return 1
        case .imu: return 2
        }
    }

    init?(data: Data) {
        let bytes = Array(data)
        guard bytes.count == 18,
              let state = DetectionState(rawValue: bytes[10]), bytes[11] <= 1,
              [5, 14, 15, 16].allSatisfy({ bytes[$0] <= 100 }) else { return nil }

        func word(_ offset: Int) -> UInt16 {
            UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        }

        switch bytes[0] {
        case 1:
            signal = .flex(FlexSignal(rawADC: word(1), filteredADC: word(3),
                                      extensionADC: word(6), flexionADC: word(8), deadZoneADC: bytes[17]))
        case 2:
            signal = .imu(IMUSignal(rawCentidegrees: Int16(bitPattern: word(1)),
                                    filteredCentidegrees: Int16(bitPattern: word(3)),
                                    extensionCentidegrees: Int16(bitPattern: word(6)),
                                    flexionCentidegrees: Int16(bitPattern: word(8)),
                                    health: IMUHealth(rawValue: bytes[17])))
        default:
            return nil
        }

        progressPercent = bytes[5]
        detectionState = state
        calibrationValid = bytes[11] == 1
        batteryMillivolts = word(12)
        extensionThresholdPercent = bytes[14]
        flexionThresholdPercent = bytes[15]
        emaPercent = bytes[16]
    }

    func sample(at date: Date) -> SensorSample? {
        switch signal {
        case .flex(let flex):
            return SensorSample(date: date, raw: Double(flex.rawADC), filtered: Double(flex.filteredADC))
        case .imu(let imu):
            guard imu.health.hasUsableOrientation else { return nil }
            return SensorSample(date: date, raw: imu.rawDegrees, filtered: imu.filteredDegrees)
        }
    }
}

struct SensorSample: Identifiable {
    static let historyLimit = 300

    let id = UUID()
    let date: Date
    let raw: Double
    let filtered: Double
}
