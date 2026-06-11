//
//  HelperService.swift
//  
//
//  Created by John Cris Antor on 6/11/2026.
//

import Foundation
import Security
import SMCBridge
import SMCWrapperObjC

final class HelperService: NSObject, HelperProtocol, NSXPCListenerDelegate {
    private var smc: SMCWrapperObjC?
    private let smcLock = NSLock()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard isValidClient(connection: newConnection) else { return false }
        NSLog("[AirBenderHelper] Accepted XPC connection from pid \(newConnection.processIdentifier).")
        newConnection.exportedInterface = makeHelperInterface()
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    private func isValidClient(connection: NSXPCConnection) -> Bool {
        return true // TEMPORARY for debugging
    }

    func getVersion(reply: @escaping (String) -> Void) {
        reply("1.0.0")
    }

    func getFanInfo(reply: @escaping ([FanInfoDTO], Error?) -> Void) {
        do {
            let smc = try getSMC()
            let count = smc.fanCount()
            if count <= 0 {
                reply([], NSError(domain: "HelperError", code: count, userInfo: [NSLocalizedDescriptionKey: "fanCount is \(count)"]))
                return
            }
            var results: [FanInfoDTO] = []
            for i in 0..<count {
                let current = smc.fanSpeed(for: i)
                let minRPM = smc.fanMinSpeed(for: i)
                let maxRPM = smc.fanMaxSpeed(for: i)
                results.append(FanInfoDTO(index: i, currentRPM: current, minRPM: minRPM, maxRPM: maxRPM, mode: currentMode))
            }
            reply(results, nil)
        } catch {
            reply([], error)
        }
    }

    private var currentMode: FanMode = .system

    private func getSMC() throws -> SMCWrapperObjC {
        smcLock.lock()
        defer { smcLock.unlock() }

        if let smc {
            return smc
        }

        do {
            let openedSMC = try SMCWrapperObjC()
            smc = openedSMC
            NSLog("[AirBenderHelper] Opened AppleSMC connection.")
            return openedSMC
        } catch {
            NSLog("[AirBenderHelper] Failed to open AppleSMC: \(error.localizedDescription)")
            throw error
        }
    }

    func setFanMode(_ mode: FanMode, percentages: [NSNumber], reply: @escaping (Error?) -> Void) {
        do {
            let smc = try getSMC()
            let count = smc.fanCount()
            switch mode {
            case .system:
                try smc.setManualMode(enabled: false, fanCount: count)
            case .manual:
                try smc.setManualMode(enabled: true, fanCount: count)
                for (i, pctNum) in percentages.enumerated() where i < count {
                    let pct = pctNum.intValue
                    let minRPM = smc.fanMinSpeed(for: i)
                    let maxRPM = smc.fanMaxSpeed(for: i)
                    let target = minRPM + (Double(pct) / 100.0) * (maxRPM - minRPM)
                    try smc.setFanTargetSpeed(index: i, rpm: target)
                }
            case .max:
                try smc.setManualMode(enabled: true, fanCount: count)
                for i in 0..<count {
                    let maxRPM = smc.fanMaxSpeed(for: i)
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
