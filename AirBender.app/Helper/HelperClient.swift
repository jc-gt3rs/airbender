//
//  HelperClient.swift
//  
//
//  Created by John Cris Antor on 6/11/2026.
//

import Foundation
import ServiceManagement

final class HelperClient: @unchecked Sendable {
    static let shared = HelperClient()

    private var connection: NSXPCConnection?
    private let lock = NSLock()

    // MARK: - Helper Installation

    /// Installs the privileged helper via SMJobBless.
    /// This registers the helper with launchd so XPC connections can reach it.
    /// Prompts the user for admin credentials on first install.
    @discardableResult
    func installHelper() -> Bool {
        let service = SMAppService.daemon(plistName: "com.airbender.helper.plist")
        
        switch service.status {
        case .enabled:
            NSLog("[AirBender] Helper is already enabled via SMAppService.")
            return true
        case .requiresApproval:
            NSLog("[AirBender] ⚠️ HELPER DISABLED IN SYSTEM SETTINGS. Please go to System Settings > General > Login Items and turn ON the background item for AirBender!")
            return true // return true so we still attempt connection, but it will fail until they approve
        case .notFound:
            do {
                try service.register()
                NSLog("[AirBender] Helper installed successfully. Status: \(service.status.rawValue)")
                return true
            } catch {
                NSLog("[AirBender] SMAppService failed to register: \(error.localizedDescription)")
                return false
            }
        @unknown default:
            return false
        }
    }

    // MARK: - XPC Connection

    private func makeConnection() -> NSXPCConnection {
        let conn = NSXPCConnection(machServiceName: "com.airbender.helper", options: .privileged)
        conn.remoteObjectInterface = makeHelperInterface()
        conn.exportedInterface = nil
        conn.invalidationHandler = { [weak self] in
            guard let self else { return }
            self.lock.withLock { self.connection = nil }
        }
        conn.interruptionHandler = { [weak self] in
            guard let self else { return }
            self.lock.withLock { self.connection = nil }
        }
        conn.resume()
        return conn
    }

    private func getConnection() -> NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }
        if let existing = connection {
            return existing
        }
        let conn = makeConnection()
        connection = conn
        return conn
    }

    // MARK: - RPC Methods

    func fetchFanInfo() async throws -> [FanInfoDTO] {
        try await withCheckedThrowingContinuation { continuation in
            let conn = getConnection()
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                NSLog("[AirBender] XPC Error in fetchFanInfo: \(error)")
                continuation.resume(throwing: error)
            } as! HelperProtocol

            proxy.getFanInfo { info, error in
                if let error {
                    NSLog("[AirBender] Helper returned error: \(error)")
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: info)
                }
            }
        }
    }

    func setMode(_ mode: FanMode, percentages: [Int]) async throws {
        let nsPercentages = percentages.map { NSNumber(value: $0) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let conn = getConnection()
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as! HelperProtocol

            proxy.setFanMode(mode, percentages: nsPercentages) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
