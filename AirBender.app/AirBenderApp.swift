//
//  AirBenderApp.swift
//  
//
//  Created by John Cris Antor on 6/11/2026.
//

import SwiftUI

@main
struct AirBenderApp: App {
    @State private var viewModel = FanControlViewModel()

    init() {
        // Install the privileged helper via SMJobBless on launch.
        // This is a no-op if the helper is already installed at the current version.
        // Prompts the user for admin credentials if needed.
        let success = HelperClient.shared.installHelper()
        if !success {
            NSLog("[AirBender] WARNING: Helper installation failed. Fan control will not work until the helper is installed.")
        }
    }

    var body: some Scene {
        MenuBarExtra("AirBender", systemImage: "fan.fill") {
            FanControlPopoverView(viewModel: viewModel)
                .frame(width: 320)
                .onAppear { viewModel.startMonitoring() }
                .onDisappear { viewModel.stopMonitoring() }
        }
        .menuBarExtraStyle(.window)
    }
}
