import Foundation
import XCTest
@testable import CotoveleiraInteligente

final class DiagnosticTelemetryTests: XCTestCase {
    private let legacy: [UInt8] = [
        1, 0x0A, 0x0A, 0x3A, 0x02, 80, 0x0A, 0x0A, 0x3A, 0x02,
        2, 1, 0x74, 0x0E, 20, 80, 15, 30
    ]
    private let imu: [UInt8] = [
        2, 0x2E, 0xFB, 0xD2, 0x04, 73, 0x00, 0x80, 0xFF, 0x7F,
        3, 1, 0x74, 0x0E, 21, 81, 16, 0b011
    ]

    func testLegacyPacketPreservesADCAndDeadZone() throws {
        let telemetry = try XCTUnwrap(DiagnosticTelemetry(data: Data(legacy)))
        guard case .flex(let flex) = telemetry.signal else { return XCTFail("Expected ADC") }
        XCTAssertEqual(telemetry.version, 1)
        XCTAssertEqual(flex.rawADC, 2570)
        XCTAssertEqual(flex.filteredADC, 570)
        XCTAssertEqual(flex.extensionADC, 2570)
        XCTAssertEqual(flex.flexionADC, 570)
        XCTAssertEqual(flex.deadZoneADC, 30)
        XCTAssertEqual(telemetry.progressPercent, 80)
        XCTAssertEqual(telemetry.detectionState, .waitingForReturn)
        XCTAssertTrue(telemetry.calibrationValid)
        XCTAssertEqual(telemetry.batteryMillivolts, 3700)
        XCTAssertEqual(telemetry.extensionThresholdPercent, 20)
        XCTAssertEqual(telemetry.flexionThresholdPercent, 80)
        XCTAssertEqual(telemetry.emaPercent, 15)
        XCTAssertEqual(telemetry.sample(at: .now)?.raw, 2570)
    }

    func testIMUDecodesSignedLittleEndianAndConvertsToDegrees() throws {
        let packet = Data([0xFF] + imu).dropFirst()
        let telemetry = try XCTUnwrap(DiagnosticTelemetry(data: packet))
        guard case .imu(let signal) = telemetry.signal else { return XCTFail("Expected IMU") }
        XCTAssertEqual(telemetry.version, 2)
        XCTAssertEqual(signal.rawCentidegrees, -1234)
        XCTAssertEqual(signal.filteredCentidegrees, 1234)
        XCTAssertEqual(signal.extensionCentidegrees, Int16.min)
        XCTAssertEqual(signal.flexionCentidegrees, Int16.max)
        XCTAssertEqual(signal.rawDegrees, -12.34, accuracy: 0.0001)
        XCTAssertEqual(signal.filteredDegrees, 12.34, accuracy: 0.0001)
        XCTAssertEqual(signal.extensionDegrees, -327.68, accuracy: 0.0001)
        XCTAssertEqual(signal.flexionDegrees, 327.67, accuracy: 0.0001)
        XCTAssertEqual(telemetry.progressPercent, 73)
        XCTAssertEqual(telemetry.detectionState, .reset)
        XCTAssertTrue(telemetry.calibrationValid)
        XCTAssertEqual(telemetry.batteryMillivolts, 3700)
        XCTAssertEqual(telemetry.extensionThresholdPercent, 21)
        XCTAssertEqual(telemetry.flexionThresholdPercent, 81)
        XCTAssertEqual(telemetry.emaPercent, 16)
        XCTAssertEqual(signal.health, [.detected, .orientationValid])
        XCTAssertEqual(telemetry.sample(at: .now)?.raw, -12.34)
    }

    func testIntegrityFlagsAndReservedBits() throws {
        let flags: [UInt8] = [0, 1, 2, 3, 4, 7, 0x83]
        for raw in flags {
            var bytes = imu
            bytes[11] = 0
            bytes[17] = raw
            let telemetry = try XCTUnwrap(DiagnosticTelemetry(data: Data(bytes)))
            guard case .imu(let signal) = telemetry.signal else { return XCTFail("Expected IMU") }
            XCTAssertFalse(telemetry.calibrationValid)
            XCTAssertEqual(signal.health.rawValue, raw)
            XCTAssertEqual(signal.health.contains(.detected), raw & 1 != 0)
            XCTAssertEqual(signal.health.contains(.orientationValid), raw & 2 != 0)
            XCTAssertEqual(signal.health.contains(.i2cError), raw & 4 != 0)
            XCTAssertEqual(telemetry.sample(at: .now) != nil, raw == 3 || raw == 0x83)
        }
    }

    func testRejectsInvalidPayloadsForBothVersions() {
        for valid in [legacy, imu] {
            for count in 0..<valid.count {
                XCTAssertNil(DiagnosticTelemetry(data: Data(valid.prefix(count))))
            }
            XCTAssertNil(DiagnosticTelemetry(data: Data(valid + [0])))
            let invalidFields: [(Int, UInt8)] = [(0, 3), (5, 101), (10, 4), (11, 2), (14, 101), (15, 101), (16, 101)]
            for (offset, bad) in invalidFields {
                var invalid = valid
                invalid[offset] = bad
                XCTAssertNil(DiagnosticTelemetry(data: Data(invalid)), "offset \(offset)")
            }
        }
    }
}
