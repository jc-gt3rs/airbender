//
//  SMCWrapper.swift
//  
//
//  Created by John Cris Antor on 6/11/2026.
//

import Foundation
import IOKit
import SMCBridge

enum SMCError: Error, LocalizedError {
    case openFailed
    case keyNotFound(String)
    case readFailed(String, kern_return_t)
    case writeFailed(String, kern_return_t)

    var errorDescription: String? {
        switch self {
        case .openFailed:
            return "Could not open connection to AppleSMC."
        case .keyNotFound(let key):
            return "SMC key not found: \(key)"
        case .readFailed(let key, let code):
            return "Failed to read \(key): IOKit error \(code)"
        case .writeFailed(let key, let code):
            return "Failed to write \(key): IOKit error \(code)"
        }
    }
}

/// Thread-safe, typesafe wrapper around the AppleSMC IOKit connection.
final class SMCWrapper {
    private var connection: io_connect_t = 0
    private let lock = NSLock()

    init() throws {
        let conn = SMCOpen()
        guard conn != 0 else { throw SMCError.openFailed }
        self.connection = conn
    }

    deinit {
        if connection != 0 {
            SMCClose(connection)
        }
    }

    /// Reads the number of fans reported by the SMC ("FNum").
    func fanCount() throws -> Int {
        var val = SMCVal_t()
        let result = SMCReadKey(connection, "FNum", &val)
        guard result == kIOReturnSuccess else {
            throw SMCError.readFailed("FNum", result)
        }
        return Int(val.bytes.0)
    }

    /// Reads current fan speed in RPM for a given fan index.
    func fanSpeed(index: Int) throws -> Double {
        let key = "F\(index)Ac"
        return try readFloatKey(key)
    }

    /// Reads minimum allowed RPM for a given fan index.
    func fanMinSpeed(index: Int) throws -> Double {
        try readFloatKey("F\(index)Mn")
    }

    /// Reads maximum allowed RPM for a given fan index.
    func fanMaxSpeed(index: Int) throws -> Double {
        try readFloatKey("F\(index)Mx")
    }

    /// Sets a manual target RPM for a given fan index.
    /// Writing to "F{n}Tg" requests a target speed; the SMC will also
    /// require "FS! " bitmask to be set for manual mode to take effect.
    func setFanTargetSpeed(index: Int, rpm: Double) throws {
        try writeFloatKey("F\(index)Tg", value: rpm)
    }

    /// Enables manual control mode by setting the FS! bitmask.
    /// Each bit corresponds to a fan index (bit 0 = fan 0, etc).
    func setManualMode(enabled: Bool, fanCount: Int) throws {
        var mask: UInt16 = 0
        if enabled {
            for i in 0..<fanCount {
                mask |= (1 << i)
            }
        }
        var val = SMCVal_t()
        val.key = SMCKeyToUInt32("FS! ")
        val.dataType = SMCKeyToUInt32("ui16")
        let be = mask.bigEndian
        val.bytes.0 = UInt8(truncatingIfNeeded: be >> 8)
        val.bytes.1 = UInt8(truncatingIfNeeded: be)
        let result = SMCWriteKey(connection, val)
        guard result == kIOReturnSuccess else {
            throw SMCError.writeFailed("FS!", result)
        }
    }

    // MARK: - Private helpers

    private func readFloatKey(_ key: String) throws -> Double {
        var val = SMCVal_t()
        let result = SMCReadKey(connection, key, &val)
        guard result == kIOReturnSuccess else {
            throw SMCError.readFailed(key, result)
        }
        return decodeFloatBytes(val.bytes, dataType: val.dataType)
    }

    private func writeFloatKey(_ key: String, value: Double) throws {
        var val = SMCVal_t()
        val.key = SMCKeyToUInt32(key)
        // Most fan keys use "fpe2" (fixed point, 2 fraction bits)
        val.dataType = SMCKeyToUInt32("fpe2")
        let scaled = UInt16(clamping: Int(value * 4.0))
        let be = scaled.bigEndian
        val.bytes.0 = UInt8(truncatingIfNeeded: be >> 8)
        val.bytes.1 = UInt8(truncatingIfNeeded: be)
        let result = SMCWriteKey(connection, val)
        guard result == kIOReturnSuccess else {
            throw SMCError.writeFailed(key, result)
        }
    }

    private func decodeFloatBytes(_ bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8), dataType: UInt32) -> Double {
        // "fpe2" format: 16-bit big endian, 2 fractional bits
        let raw = (UInt16(bytes.0) << 8) | UInt16(bytes.1)
        return Double(raw) / 4.0
    }
}
