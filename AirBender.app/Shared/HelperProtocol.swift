//
//  HelperProtocol.swift
//  
//
//  Created by John Cris Antor on 6/11/2026.
//

import Foundation

@objc(FanMode) enum FanMode: Int, Codable {
    case system = 0
    case manual = 1
    case max = 2
}

@objc(HelperProtocol) protocol HelperProtocol {
    func getFanInfo(reply: @escaping ([FanInfoDTO], Error?) -> Void)
    func setFanMode(_ mode: FanMode, percentages: [NSNumber], reply: @escaping (Error?) -> Void)
    func getVersion(reply: @escaping (String) -> Void)
}

@objc(FanInfoDTO) final class FanInfoDTO: NSObject, NSSecureCoding, Codable, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { return true }

    let index: Int
    let currentRPM: Double
    let minRPM: Double
    let maxRPM: Double
    let mode: FanMode

    init(index: Int, currentRPM: Double, minRPM: Double, maxRPM: Double, mode: FanMode) {
        self.index = index
        self.currentRPM = currentRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.mode = mode
    }

    func encode(with coder: NSCoder) {
        coder.encode(index, forKey: "index")
        coder.encode(currentRPM, forKey: "currentRPM")
        coder.encode(minRPM, forKey: "minRPM")
        coder.encode(maxRPM, forKey: "maxRPM")
        coder.encode(mode.rawValue, forKey: "mode")
    }

    init?(coder: NSCoder) {
        index = coder.decodeInteger(forKey: "index")
        currentRPM = coder.decodeDouble(forKey: "currentRPM")
        minRPM = coder.decodeDouble(forKey: "minRPM")
        maxRPM = coder.decodeDouble(forKey: "maxRPM")
        mode = FanMode(rawValue: coder.decodeInteger(forKey: "mode")) ?? .system
    }
}

/// Creates a properly configured `NSXPCInterface` for `HelperProtocol`,
/// with custom class whitelists for XPC serialization of `FanInfoDTO` and `NSNumber` arrays.
func makeHelperInterface() -> NSXPCInterface {
    let interface = NSXPCInterface(with: HelperProtocol.self)

    // getFanInfo reply block parameter 0: [FanInfoDTO]
    let fanInfoClasses = NSSet(array: [NSArray.self, FanInfoDTO.self]) as! Set<AnyHashable>
    interface.setClasses(
        fanInfoClasses,
        for: #selector(HelperProtocol.getFanInfo(reply:)),
        argumentIndex: 0,
        ofReply: true
    )

    // setFanMode percentages parameter (argument index 1, not of reply)
    let numberClasses = NSSet(array: [NSArray.self, NSNumber.self]) as! Set<AnyHashable>
    interface.setClasses(
        numberClasses,
        for: #selector(HelperProtocol.setFanMode(_:percentages:reply:)),
        argumentIndex: 1,
        ofReply: false
    )

    return interface
}
