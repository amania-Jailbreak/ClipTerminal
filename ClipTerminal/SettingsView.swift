import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var launchAtLogin: Bool = false
    @AppStorage("showDockIcon") private var showDockIcon: Bool = false
    @AppStorage("autoPaste") private var autoPaste: Bool = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunchAtLogin(enabled: newValue)
                    }
                
                Toggle("Show Dock Icon", isOn: $showDockIcon)
                    .onChange(of: showDockIcon) { _, newValue in
                        updateDockIcon(show: newValue)
                    }
                
                Toggle("Auto-Paste on Selection", isOn: $autoPaste)
            } footer: {
                Text("Auto-Paste requires Accessibility permissions to simulate Command+V.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section {
                Text("ClipTerminal v1.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 250)
        .onAppear {
            checkLaunchAtLogin()
            // Sync Dock icon state on appear just in case
            updateDockIcon(show: showDockIcon)
        }
    }
    
    private func updateDockIcon(show: Bool) {
        if show {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    private func checkLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
    
    private func toggleLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update Launch at Login: \(error)")
                launchAtLogin = !enabled
            }
        }
    }
}