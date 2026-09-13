import AppKit
import HealthCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Make it yours").font(.system(size: 21, weight: .medium, design: .rounded))
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Google account", symbol: "person.crop.circle", color: Palette.green)
                    HStack {
                        Circle().fill(store.isConnected ? Palette.green : .secondary).frame(width: 6, height: 6)
                        Text(store.isConnected ? "Connected to Google Health" : "Not connected").font(.system(size: 12, weight: .medium))
                    }
                    if let config = store.auth.configuration {
                        Text("OAuth project: \(config.installed.project_id)").font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    HStack {
                        Button(store.auth.isSigningIn ? "Waiting for Google…" : store.isConnected ? "Reconnect" : "Connect with Google") { store.connect() }
                            .buttonStyle(.borderedProminent).disabled(store.auth.isSigningIn)
                        if store.auth.isSigningIn { Button("Cancel") { store.auth.cancelSignIn() } }
                        else if store.isConnected { Button("Disconnect") { store.disconnect() } }
                    }.controlSize(.small)
                    Button("Import OAuth JSON…") { store.chooseConfiguration() }.buttonStyle(.link).font(.system(size: 11))
                    Text("Read-only access to sleep, activity, vitals, and devices. Credentials and tokens are saved in Keychain. Health readings are kept in memory and cleared on disconnect.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
                }
            }
            Surface {
                VStack(alignment: .leading, spacing: 13) {
                    SectionLabel(title: "In your menu bar", symbol: "menubar.rectangle", color: Palette.blue)
                    settingToggle("Heart rate", binding: $store.showHeart)
                    settingToggle("Sleep duration", binding: $store.showSleep)
                    settingToggle("Steps", binding: $store.showSteps)
                    settingToggle("Heart rate variability", binding: $store.showHRV)
                    Text("A trailing dot marks an older reading. Open Air Stats to see its date and time.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }.font(.system(size: 12)).toggleStyle(.switch).controlSize(.mini)
            }
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Preferences", symbol: "gearshape", color: Palette.purple)
                    Picker("Refresh every", selection: $store.refreshInterval) {
                        Text("1 minute").tag(60.0)
                        Text("5 minutes").tag(300.0)
                        Text("15 minutes").tag(900.0)
                    }.font(.system(size: 12))
                    Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
                        .toggleStyle(.switch).controlSize(.mini).font(.system(size: 12))
                    Text("Refreshing checks Google's latest synced data. Sync your tracker in the phone app for newer readings.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !store.snapshot.issues.isEmpty {
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Connection details", symbol: "exclamationmark.circle", color: Palette.gold)
                        ForEach(store.snapshot.issues.keys.sorted(), id: \.self) { key in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(key.replacingOccurrences(of: "-", with: " ").capitalized).font(.system(size: 11, weight: .medium))
                                Text(store.snapshot.issues[key] ?? "").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            HStack {
                Button(store.isDemo ? "Exit preview" : "Preview sample data") { if store.isDemo { store.endPreview() } else { store.preview() } }
                Spacer()
                Button("Quit Air Stats") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }.buttonStyle(.link).font(.system(size: 11))
            Link("Manage Google permissions ↗", destination: URL(string: "https://myaccount.google.com/connections")!)
                .font(.system(size: 10))
            Text("Air Stats 1.0 · An independent Fitbit companion").font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
    private func settingToggle(_ title: String, binding: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: binding).labelsHidden().accessibilityLabel(title)
        }
    }
}
