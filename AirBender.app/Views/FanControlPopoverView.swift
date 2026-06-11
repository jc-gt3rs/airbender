//
//  FanControlPopoverView.swift
//  
//
//  Created by John Cris Antor on 6/11/2026.
//

import SwiftUI

struct FanControlPopoverView: View {
    @Bindable var viewModel: FanControlViewModel

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                header

                switch viewModel.connectionState {
                case .connecting:
                    connectingView
                case .error(let message):
                    errorView(message)
                case .connected:
                    fanList
                    actionButtons
                }
            }
            .padding(16)
        }
    }

    private var header: some View {
        HStack {
            if #available(macOS 15.0, *) {
                Image(systemName: "fan.fill")
                    .font(.title2)
                    .symbolEffect(.rotate, options: .repeating, isActive: viewModel.activeMode != .system)
            } else {
                Image(systemName: "fan.fill")
                    .font(.title2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("AirBender")
                    .font(.headline)
                Text(modeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
    }

    private var modeDescription: String {
        switch viewModel.activeMode {
        case .system: return "System Controlled"
        case .manual: return "Manual Override"
        case .max: return "Maximum Speed"
        }
    }

    private var connectingView: some View {
        VStack(spacing: 12) {
            ProgressView("Connecting to helper...")

            Button(viewModel.isInstallingHelper ? "Repairing..." : "Repair Helper") {
                Task { await viewModel.installOrRepairHelper() }
            }
            .disabled(viewModel.isInstallingHelper)
        }
        .padding(.vertical, 24)
    }

    private var fanList: some View {
        VStack(spacing: 14) {
            ForEach(Array(viewModel.fans.enumerated()), id: \.offset) { index, fan in
                FanSliderRow(
                    title: "Fan \(index + 1)",
                    rpm: Int(fan.currentRPM),
                    percentage: Binding(
                        get: { viewModel.sliderPercentages.indices.contains(index) ? viewModel.sliderPercentages[index] : 0 },
                        set: { newValue in
                            Task { await viewModel.applyManualSpeed(fanIndex: index, percentage: newValue) }
                        }
                    )
                )
                .disabled(viewModel.activeMode != .manual)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                Task { await viewModel.returnToSystemControl() }
            } label: {
                Label("Auto", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassButtonStyle(isActive: viewModel.activeMode == .system))

            Button {
                Task { await viewModel.setManualMode() }
            } label: {
                Label("Manual", systemImage: "hand.tap")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassButtonStyle(isActive: viewModel.activeMode == .manual, tint: .blue))

            Button {
                Task { await viewModel.setMaxSpeed() }
            } label: {
                Label("Max", systemImage: "wind")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassButtonStyle(isActive: viewModel.activeMode == .max, tint: .red))
        }
        .disabled(viewModel.isApplyingChange)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Retry") {
                    Task { await viewModel.refresh() }
                }

                Button(viewModel.isInstallingHelper ? "Repairing..." : "Repair Helper") {
                    Task { await viewModel.installOrRepairHelper() }
                }
                .disabled(viewModel.isInstallingHelper)

                Button("Open Settings") {
                    viewModel.openHelperApprovalSettings()
                }
            }
        }
        .padding(.vertical, 24)
    }
}

private struct FanSliderRow: View {
    let title: String
    let rpm: Int
    @Binding var percentage: Int

    @State private var displayValue: Double

    init(title: String, rpm: Int, percentage: Binding<Int>) {
        self.title = title
        self.rpm = rpm
        self._percentage = percentage
        self._displayValue = State(initialValue: Double(percentage.wrappedValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(rpm) RPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Int(displayValue))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }

            Slider(
                value: $displayValue,
                in: 25...100,
                step: 25,
                onEditingChanged: { editing in
                    if !editing {
                        percentage = Int(displayValue)
                    }
                }
            )
            .tint(.accentColor)
        }
        .onChange(of: percentage) { _, newValue in
            displayValue = Double(newValue)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: displayValue)
    }
}

private struct GlassButtonStyle: ButtonStyle {
    var isActive: Bool = false
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? tint.opacity(0.25) : Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isActive ? tint.opacity(0.5) : Color.primary.opacity(0.1), lineWidth: 1)
                    )
            )
            .foregroundStyle(isActive ? tint : Color.primary)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
