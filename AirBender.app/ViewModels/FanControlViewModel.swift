//
//  FanControlViewModel.swift
//  
//
//  Created by John Cris Antor on 6/11/2026.
//

import Foundation
import Observation

@Observable
final class FanControlViewModel {
    enum ConnectionState: Equatable {
        case connecting
        case connected
        case error(String)
    }

    var fans: [FanInfoDTO] = []
    var sliderPercentages: [Int] = []
    var activeMode: FanMode = .system
    var connectionState: ConnectionState = .connecting
    var isApplyingChange: Bool = false
    var isInstallingHelper: Bool = false

    private let client = HelperClient.shared
    private var refreshTask: Task<Void, Never>?

    @MainActor
    func startMonitoring() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopMonitoring() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    @MainActor
    func refresh() async {
        do {
            let info = try await client.fetchFanInfo()
            self.fans = info
            if sliderPercentages.count != info.count {
                sliderPercentages = info.map { percentage(for: $0) }
            }
            self.activeMode = info.first?.mode ?? .system
            self.connectionState = .connected
        } catch {
            self.connectionState = .error(error.localizedDescription)
        }
    }

    @MainActor
    func installOrRepairHelper() async {
        guard !isInstallingHelper else { return }
        isInstallingHelper = true
        connectionState = .connecting
        defer { isInstallingHelper = false }

        let client = self.client
        do {
            try await Task.detached {
                try client.installOrRepairHelper(forceRepair: true)
            }.value
            await refresh()
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    func openHelperApprovalSettings() {
        client.openHelperApprovalSettings()
    }

    @MainActor
    func applyManualSpeed(fanIndex: Int, percentage: Int) async {
        guard fans.indices.contains(fanIndex) else { return }
        sliderPercentages[fanIndex] = percentage
        isApplyingChange = true
        defer { isApplyingChange = false }

        do {
            try await client.setMode(.manual, percentages: sliderPercentages)
            activeMode = .manual
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    @MainActor
    func setMaxSpeed() async {
        isApplyingChange = true
        defer { isApplyingChange = false }
        sliderPercentages = Array(repeating: 100, count: fans.count)
        do {
            try await client.setMode(.max, percentages: sliderPercentages)
            activeMode = .max
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    @MainActor
    func setManualMode() async {
        isApplyingChange = true
        defer { isApplyingChange = false }
        do {
            try await client.setMode(.manual, percentages: sliderPercentages)
            activeMode = .manual
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    @MainActor
    func returnToSystemControl() async {
        isApplyingChange = true
        defer { isApplyingChange = false }
        do {
            try await client.setMode(.system, percentages: [])
            activeMode = .system
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    private func percentage(for fan: FanInfoDTO) -> Int {
        guard fan.maxRPM > fan.minRPM else { return 0 }
        let ratio = (fan.currentRPM - fan.minRPM) / (fan.maxRPM - fan.minRPM)
        return Int((ratio * 100).rounded())
    }
}
