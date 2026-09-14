import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @StateObject private var agentIntegration = AgentIntegrationController()
    @State private var confirmDisconnect = false
    @State private var confirmAgentSetup = false
    var body: some View {
        Form {
            if let error = store.error ?? store.auth.error {
                Section("Connection needs attention") {
                    Text(error).foregroundStyle(.secondary).textSelection(.enabled)
                    Button("Dismiss error") { store.error = nil; store.auth.error = nil }
                }
            }
            Section {
                LabeledContent("Status") {
                    Label(store.isConnected ? "Connected" : "Not connected", systemImage: store.isConnected ? "checkmark.circle.fill" : "person.crop.circle.badge.questionmark")
                        .foregroundStyle(store.isConnected ? Color.accentColor : Color.secondary)
                }
                if let config = store.auth.configuration {
                    LabeledContent("OAuth project", value: config.installed.project_id).textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    Button { store.connect() } label: {
                        Text(store.auth.isSigningIn ? "Waiting for Google…" : store.isConnected ? "Reconnect" : "Connect with Google").foregroundStyle(.white)
                    }.modifier(PrimaryButtonStyle()).disabled(store.auth.isSigningIn)
                    if store.auth.isSigningIn { Button("Cancel sign-in") { store.auth.cancelSignIn() } }
                    else if store.isConnected { Button("Disconnect", role: .destructive) { confirmDisconnect = true } }
                }
                Button("Import OAuth JSON…") { store.chooseConfiguration() }
            } header: { Text("Google account") }
            footer: { Text("Read-only access. Credentials and tokens stay in Keychain. Health readings are cleared when you disconnect.") }

            Section {
                Toggle("Heart rate", isOn: $store.showHeart)
                Toggle("Sleep duration", isOn: $store.showSleep)
                Toggle("Steps", isOn: $store.showSteps)
                Toggle("Heart rate variability", isOn: $store.showHRV)
            } header: { Text("In your menu bar") }
            footer: { Text("A trailing dot marks an older reading. Open Air Stats to see its timestamp.") }

            Section {
                Picker("Refresh every", selection: $store.refreshInterval) {
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                    Text("15 minutes").tag(900.0)
                }
                Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
            } header: { Text("Preferences") }
            footer: { Text("Refresh checks Google's latest synced data. Sync your tracker in the phone app for newer readings.") }

            Section {
                LabeledContent("Status") {
                    if agentIntegration.isWorking {
                        ProgressView().controlSize(.small).accessibilityLabel("Checking agent access")
                    } else {
                        Label(agentIntegration.status,
                              systemImage: agentIntegration.isInstalled ? "checkmark.circle.fill" : "sparkles")
                            .foregroundStyle(agentIntegration.isInstalled ? Color.accentColor : Color.secondary)
                    }
                }
                if let detail = agentIntegration.detail {
                    Text(detail).foregroundStyle(.secondary).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Button(agentIntegration.isInstalled ? "Update agent access…" : "Set up agent access…") {
                        confirmAgentSetup = true
                    }
                    .disabled(agentIntegration.isWorking || store.isDemo || !store.isConnected)
                    if agentIntegration.hasAnyInstallation {
                        Button("Remove agent access", role: .destructive) { agentIntegration.uninstall() }
                            .disabled(agentIntegration.isWorking)
                    }
                }
            } header: { Text("Claude Code and Codex") }
            footer: {
                Text(store.isDemo
                     ? "Agent access is unavailable while previewing sample data."
                     : store.isConnected
                        ? "Installs a local, read-only tool and health skill. When you ask about your health, the selected agent sends those readings to its model provider. OAuth tokens stay in Keychain."
                        : "Connect your Google account before setting up agent access.")
            }
            .task { if !store.isDemo { agentIntegration.refresh() } }

            Section {
                LabeledContent("Version", value: store.updates.installedVersionLabel)
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { store.updates.automaticallyChecksForUpdates },
                    set: { store.updates.automaticallyChecksForUpdates = $0 }
                ))
                Toggle("Count this install anonymously", isOn: Binding(
                    get: { store.updates.sharesAnonymousUsage },
                    set: { store.updates.sharesAnonymousUsage = $0 }
                ))
                Button("Check for Updates…") { store.updates.checkForUpdates() }
            } header: { Text("Updates") }
            footer: {
                Text("Checks the public Air Stats releases once a day. Counting sends that same check through health.sparkles.dev with the app and macOS version, so the project can see how many people use Air Stats. No account, device identifier, or health data is sent. Turn it off to ask GitHub directly. Downloads always come from health.sparkles.dev.")
            }

            if !store.snapshot.issues.isEmpty {
                Section("Connection details") {
                    ForEach(store.snapshot.issues.keys.sorted(), id: \.self) { key in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key.replacingOccurrences(of: "-", with: " ").capitalized).fontWeight(.medium)
                            Text(store.snapshot.issues[key] ?? "").foregroundStyle(.secondary).textSelection(.enabled)
                        }.fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Section {
                Button(store.isDemo ? "Exit preview" : "Preview sample data") { if store.isDemo { store.endPreview() } else { store.preview() } }
                Link("Manage Google permissions", destination: URL(string: "https://myaccount.google.com/connections")!)
                Button("Quit Air Stats") { NSApp.terminate(nil) }.keyboardShortcut("q")
            } footer: { Text("Air Stats · An independent Fitbit companion") }
        }
        .formStyle(.grouped).scrollContentBackground(.hidden)
        .toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
        .confirmationDialog("Disconnect from Google?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { store.disconnect() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes your saved sign-in and clears the readings on this Mac. Your Fitbit data is not deleted.") }
        .confirmationDialog("Set up local agent access?", isPresented: $confirmAgentSetup, titleVisibility: .visible) {
            Button("Set up agent access") { agentIntegration.install() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Air Stats will add a read-only health tool and skill to installed copies of Claude Code and Codex. Readings are fetched only when you ask, then shared with that agent's model provider.")
        }
    }
}
