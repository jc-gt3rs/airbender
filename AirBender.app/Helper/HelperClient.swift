//
//  HelperClient.swift
//  
//
//  Created by John Cris Antor on 6/11/2026.
//

import Foundation
import Security
import ServiceManagement

final class HelperClient: @unchecked Sendable {
    static let shared = HelperClient()

    private var connection: NSXPCConnection?
    private let lock = NSLock()

    private final class PendingReply<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Error>?

        init(_ continuation: CheckedContinuation<T, Error>) {
            self.continuation = continuation
        }

        func resume(returning value: T) {
            resume(with: .success(value))
        }

        func resume(throwing error: Error) {
            resume(with: .failure(error))
        }

        private func resume(with result: Result<T, Error>) {
            lock.lock()
            guard let continuation else {
                lock.unlock()
                return
            }
            self.continuation = nil
            lock.unlock()

            switch result {
            case .success(let value):
                continuation.resume(returning: value)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Helper Installation

    private enum Constants {
        static let helperLabel = "com.airbender.helper"
        static let helperPlistName = "com.airbender.helper.plist"
        static let xpcTimeoutSeconds: TimeInterval = 5
    }

    enum HelperInstallError: LocalizedError {
        case authorizationCreateFailed(OSStatus)
        case authorizationDenied(OSStatus)
        case blessFailed(String)
        case requiresApproval
        case registrationFailed(String)
        case unavailable

        var errorDescription: String? {
            switch self {
            case .authorizationCreateFailed:
                return "Unable to start administrator authorization."
            case .authorizationDenied:
                return "Administrator authorization was denied."
            case .blessFailed(let message):
                return "Unable to install the privileged helper: \(message)"
            case .requiresApproval:
                return "AirBender needs approval in Login Items to run its helper."
            case .registrationFailed(let message):
                return "Unable to register the helper: \(message)"
            case .unavailable:
                return "The helper did not respond."
            }
        }
    }

    @discardableResult
    func installHelper() -> Bool {
        do {
            try promptForPasswordEveryTime()
            try installOrRepairHelper(forceRepair: true)
            return true
        } catch {
            NSLog("[AirBender] Helper installation failed: \(error.localizedDescription)")
            return false
        }
    }

    func installOrRepairHelper(forceRepair: Bool = false) throws {
        let service = SMAppService.daemon(plistName: Constants.helperPlistName)

        switch service.status {
        case .enabled:
            if !forceRepair {
                NSLog("[AirBender] Helper is already enabled via SMAppService.")
                return
            }
            NSLog("[AirBender] Reinstalling enabled helper to refresh launchd registration.")
            do {
                try service.unregister()
            } catch {
                NSLog("[AirBender] SMAppService failed to unregister helper before repair: \(error.localizedDescription)")
            }
            fallthrough
        case .notFound, .notRegistered:
            do {
                try service.register()
                NSLog("[AirBender] Helper registered with SMAppService. Status: \(service.status.rawValue)")
                if service.status == .enabled { return }
            } catch {
                NSLog("[AirBender] SMAppService failed to register: \(error.localizedDescription)")
            }
            try blessPrivilegedHelper()
        case .requiresApproval:
            NSLog("[AirBender] Helper requires approval; requesting administrator authorization for repair.")
            try blessPrivilegedHelper()
        @unknown default:
            try blessPrivilegedHelper()
        }
    }

    func openHelperApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func promptForPasswordEveryTime() throws {
        var authorization: AuthorizationRef?
        let createStatus = AuthorizationCreate(nil, nil, [], &authorization)
        guard createStatus == errAuthorizationSuccess, let authorization else {
            throw HelperInstallError.authorizationCreateFailed(createStatus)
        }
        defer { AuthorizationFree(authorization, [.destroyRights]) }

        let rightName = strdup(kSMRightBlessPrivilegedHelper)
        guard let rightName else { throw HelperInstallError.authorizationDenied(errAuthorizationInternal) }
        defer { free(rightName) }

        var authItem = AuthorizationItem(name: rightName, valueLength: 0, value: nil, flags: 0)
        let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
        var rights = AuthorizationRights(count: 1, items: &authItem)
        
        let status = AuthorizationCopyRights(authorization, &rights, nil, flags, nil)
        if status != errAuthorizationSuccess {
            throw HelperInstallError.authorizationDenied(status)
        }
    }

    private func blessPrivilegedHelper() throws {
        var authorization: AuthorizationRef?
        let createStatus = AuthorizationCreate(nil, nil, [], &authorization)
        guard createStatus == errAuthorizationSuccess, let authorization else {
            throw HelperInstallError.authorizationCreateFailed(createStatus)
        }
        defer { AuthorizationFree(authorization, [.destroyRights]) }

        let rightName = strdup(kSMRightBlessPrivilegedHelper)
        guard let rightName else { throw HelperInstallError.authorizationDenied(errAuthorizationInternal) }
        defer { free(rightName) }

        var authItem = AuthorizationItem(name: rightName, valueLength: 0, value: nil, flags: 0)
        let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
        let rightsStatus = withUnsafeMutablePointer(to: &authItem) { itemPointer in
            var rights = AuthorizationRights(count: 1, items: itemPointer)
            return AuthorizationCopyRights(authorization, &rights, nil, flags, nil)
        }
        guard rightsStatus == errAuthorizationSuccess else {
            throw HelperInstallError.authorizationDenied(rightsStatus)
        }

        var unmanagedError: Unmanaged<CFError>?
        let success = SMJobBless(
            kSMDomainSystemLaunchd,
            Constants.helperLabel as CFString,
            authorization,
            &unmanagedError
        )
        guard success else {
            let message = unmanagedError?.takeRetainedValue().localizedDescription ?? "Unknown ServiceManagement error."
            throw HelperInstallError.blessFailed(message)
        }

        invalidateConnection()
        NSLog("[AirBender] Privileged helper installed/repaired with administrator authorization.")
    }

    // MARK: - XPC Connection

    private func makeConnection() -> NSXPCConnection {
        let conn = NSXPCConnection(machServiceName: Constants.helperLabel, options: .privileged)
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
            let pending = PendingReply<[FanInfoDTO]>(continuation)
            scheduleTimeout(for: pending)

            let conn = self.getConnection()
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                NSLog("[AirBender] XPC Error in fetchFanInfo: \(error)")
                pending.resume(throwing: error)
            } as! HelperProtocol

            proxy.getFanInfo { info, error in
                if let error {
                    NSLog("[AirBender] Helper returned error: \(error)")
                    pending.resume(throwing: error)
                } else {
                    pending.resume(returning: info)
                }
            }
        }
    }

    func setMode(_ mode: FanMode, percentages: [Int]) async throws {
        let nsPercentages = percentages.map { NSNumber(value: $0) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let pending = PendingReply<Void>(continuation)
            scheduleTimeout(for: pending)

            let conn = self.getConnection()
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                pending.resume(throwing: error)
            } as! HelperProtocol

            proxy.setFanMode(mode, percentages: nsPercentages) { error in
                if let error {
                    pending.resume(throwing: error)
                } else {
                    pending.resume(returning: ())
                }
            }
        }
    }

    private func scheduleTimeout<T>(for pending: PendingReply<T>) {
        DispatchQueue.global().asyncAfter(deadline: .now() + Constants.xpcTimeoutSeconds) { [weak self] in
            self?.invalidateConnection()
            pending.resume(throwing: HelperInstallError.unavailable)
        }
    }

    private func invalidateConnection() {
        lock.withLock {
            connection?.invalidate()
            connection = nil
        }
    }
}
