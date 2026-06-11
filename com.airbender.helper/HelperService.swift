//
//  HelperService.swift
//  
//
//  Created by John Cris Antor on 6/11/2026.
//

import Foundation
import Security

final class HelperService: NSObject, HelperProtocol, NSXPCListenerDelegate {
    private let smc: SMCWrapper?

    override init() {
        self.smc = try? SMCWrapper()
        super.init()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard isValidClient(connection: newConnection) else { return false }
        newConnection.exportedInterface = makeHelperInterface()
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    private func isValidClient(connection: NSXPCConnection) -> Bool {
        // Use processIdentifier (public API) to obtain a SecCode for the connecting process.
        let pid = connection.processIdentifier

        let attributes = [
            kSecGuestAttributePid as String: pid
        ] as NSDictionary

        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code) == errSecSuccess,
              let code else {
            return false
        }

        // For development, we relax the requirement to just the identifier.
        // For production, you MUST include: and certificate leaf[subject.OU] = "YOUR_TEAM_ID"
        let requirementString = "identifier \"com.airbender.app\""
        var requirement: SecRequirement?
        SecRequirementCreateWithString(requirementString as CFString, SecCSFlags(), &requirement)

        guard let requirement else {
            NSLog("[AirBender-Helper] Failed to create requirement string")
            return false
        }
        
        let status = SecCodeCheckValidity(code, SecCSFlags(), requirement)
        if status != errSecSuccess {
            NSLog("[AirBender-Helper] XPC Connection rejected: client failed validation (status: \(status))")
            return false
        }
        
        return true
    }

    func getVersion(reply: @escaping (String) -> Void) {
        reply("1.0.0")
    }

    func getFanInfo(reply: @escaping ([FanInfoDTO], Error?) -> Void) {
        guard let smc else {
            reply([], SMCError.openFailed)
            return
        }
        do {
            let count = try smc.fanCount()
            var results: [FanInfoDTO] = []
            for i in 0..<count {
                let current = try smc.fanSpeed(index: i)
                let minRPM = try smc.fanMinSpeed(index: i)
                let maxRPM = try smc.fanMaxSpeed(index: i)
                results.append(FanInfoDTO(index: i, currentRPM: current, minRPM: minRPM, maxRPM: maxRPM, mode: currentMode))
            }
            reply(results, nil)
        } catch {
            reply([], error)
        }
    }

    private var currentMode: FanMode = .system

    func setFanMode(_ mode: FanMode, percentages: [NSNumber], reply: @escaping (Error?) -> Void) {
        guard let smc else {
            reply(SMCError.openFailed)
            return
        }
        do {
            let count = try smc.fanCount()
            switch mode {
            case .system:
                try smc.setManualMode(enabled: false, fanCount: count)
            case .manual:
                try smc.setManualMode(enabled: true, fanCount: count)
                for (i, pctNum) in percentages.enumerated() where i < count {
                    let pct = pctNum.intValue
                    let minRPM = try smc.fanMinSpeed(index: i)
                    let maxRPM = try smc.fanMaxSpeed(index: i)
                    let target = minRPM + (Double(pct) / 100.0) * (maxRPM - minRPM)
                    try smc.setFanTargetSpeed(index: i, rpm: target)
                }
            case .max:
                try smc.setManualMode(enabled: true, fanCount: count)
                for i in 0..<count {
                    let maxRPM = try smc.fanMaxSpeed(index: i)
                    try smc.setFanTargetSpeed(index: i, rpm: maxRPM)
                }
            }
            currentMode = mode
            reply(nil)
        } catch {
            reply(error)
        }
    }
}
