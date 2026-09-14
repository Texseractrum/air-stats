import Combine
import Foundation

struct AgentIntegrationResult: Sendable {
    var clients: [String]
    var message: String
}

struct AgentIntegrationStatus: Sendable {
    var installedClients: [String]
    var detectedClients: [String]
    var hasAnyInstallation: Bool
    var isComplete: Bool { !detectedClients.isEmpty && installedClients.count == detectedClients.count }
}

struct AgentIntegration: @unchecked Sendable {
    static let serverName = "airstats-health"
    static let enabledDefaultsKey = "agentIntegrationEnabled"

    private enum Client: String, CaseIterable, Sendable {
        case codex = "Codex"
        case claude = "Claude Code"

        var skillComponents: [String] {
            switch self {
            case .codex: return [".agents", "skills", AgentIntegration.serverName]
            case .claude: return [".claude", "skills", AgentIntegration.serverName]
            }
        }
    }

    private let files = FileManager.default
    private let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    func install() throws -> AgentIntegrationResult {
        let detected = detectedClients()
        guard !detected.isEmpty else {
            throw IntegrationError("Install Claude Code or Codex first, then try again.")
        }
        let skillData = try bundledSkillData()
        let server = try installStableServer()
        var installed: [String] = []
        var failures: [String] = []
        for (client, executable) in detected {
            do {
                try installSkill(skillData, for: client)
                try configure(client, executable: executable, server: server)
                installed.append(client.rawValue)
            } catch {
                failures.append("\(client.rawValue): \(error.localizedDescription)")
            }
        }
        guard failures.isEmpty else {
            throw IntegrationError("Agent access was only partly installed. \(failures.joined(separator: " "))")
        }
        UserDefaults.standard.set(true, forKey: Self.enabledDefaultsKey)
        return AgentIntegrationResult(clients: installed, message: "Installed for \(joined(installed)). Start a new agent session to use it.")
    }

    func uninstall() throws -> AgentIntegrationResult {
        let detected = detectedClients()
        var removed: [String] = []
        var failures: [String] = []
        for (client, executable) in detected {
            let arguments: [String]
            switch client {
            case .codex: arguments = ["mcp", "remove", Self.serverName]
            case .claude: arguments = ["mcp", "remove", "--scope", "user", Self.serverName]
            }
            let result = try run(executable, arguments: arguments)
            if result.status == 0 || result.output.localizedCaseInsensitiveContains("not found") {
                removed.append(client.rawValue)
            } else {
                failures.append("\(client.rawValue): \(result.output)")
            }
        }
        guard failures.isEmpty else {
            throw IntegrationError("Agent access was only partly removed. \(failures.joined(separator: " "))")
        }
        for client in Client.allCases {
            let directory = skillDirectory(for: client)
            if files.fileExists(atPath: directory.path) { try files.removeItem(at: directory) }
        }
        if files.fileExists(atPath: agentDirectoryURL.path) { try files.removeItem(at: agentDirectoryURL) }
        UserDefaults.standard.set(false, forKey: Self.enabledDefaultsKey)
        return AgentIntegrationResult(clients: removed, message: "Removed Air Stats access from local agents.")
    }

    func status() -> AgentIntegrationStatus {
        let detected = detectedClients()
        var installed: [String] = []
        var hasAnyInstallation = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        for (client, executable) in detected {
            let hasSkill = files.fileExists(atPath: skillDirectory(for: client).appendingPathComponent("SKILL.md").path)
            let arguments: [String]
            switch client {
            case .codex: arguments = ["mcp", "get", Self.serverName, "--json"]
            case .claude: arguments = ["mcp", "get", Self.serverName]
            }
            let isRegistered = (try? run(executable, arguments: arguments).status) == 0
            hasAnyInstallation = hasAnyInstallation || hasSkill || isRegistered
            if hasSkill, files.fileExists(atPath: stableServerURL.path), isRegistered { installed.append(client.rawValue) }
        }
        hasAnyInstallation = hasAnyInstallation || files.fileExists(atPath: agentDirectoryURL.path)
            || Client.allCases.contains { files.fileExists(atPath: skillDirectory(for: $0).path) }
        return AgentIntegrationStatus(installedClients: installed,
                                      detectedClients: detected.map { $0.0.rawValue },
                                      hasAnyInstallation: hasAnyInstallation)
    }

    func refreshInstalledFilesIfEnabled() {
        guard UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey),
              let skillData = try? bundledSkillData(),
              (try? installStableServer()) != nil else { return }
        for client in Client.allCases where files.fileExists(atPath: skillDirectory(for: client).path) {
            try? installSkill(skillData, for: client)
        }
    }

    private var agentDirectoryURL: URL {
        home.appendingPathComponent("Library/Application Support/Air Stats/Agent")
    }

    private var stableServerBundleURL: URL { agentDirectoryURL.appendingPathComponent("Air Stats Agent.app") }
    private var stableServerURL: URL { stableServerBundleURL.appendingPathComponent("Contents/MacOS/AirStats") }

    private func bundledSkillData() throws -> Data {
        guard let url = Bundle.main.url(forResource: "SKILL", withExtension: "md",
                                        subdirectory: "AgentSkills/\(Self.serverName)") else {
            throw IntegrationError("The Air Stats agent skill is missing. Reinstall Air Stats and try again.")
        }
        return try Data(contentsOf: url)
    }

    private func installStableServer() throws -> URL {
        let source = Bundle.main.bundleURL.standardizedFileURL
        guard source.pathExtension == "app" else {
            throw IntegrationError("Open Air Stats from its app bundle, then try again.")
        }
        if source == stableServerBundleURL.standardizedFileURL { return stableServerURL }
        try files.createDirectory(at: agentDirectoryURL, withIntermediateDirectories: true)
        let temporary = agentDirectoryURL.appendingPathComponent("Air Stats Agent.\(UUID().uuidString).app")
        defer { try? files.removeItem(at: temporary) }
        try files.copyItem(at: source, to: temporary)
        if files.fileExists(atPath: stableServerBundleURL.path) { try files.removeItem(at: stableServerBundleURL) }
        try files.moveItem(at: temporary, to: stableServerBundleURL)
        let legacyServer = agentDirectoryURL.appendingPathComponent("AirStatsAgentServer")
        if files.fileExists(atPath: legacyServer.path) { try files.removeItem(at: legacyServer) }
        guard files.isExecutableFile(atPath: stableServerURL.path) else {
            throw IntegrationError("Air Stats could not prepare its local agent server.")
        }
        return stableServerURL
    }

    private func installSkill(_ data: Data, for client: Client) throws {
        let directory = skillDirectory(for: client)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("SKILL.md"), options: .atomic)
    }

    private func skillDirectory(for client: Client) -> URL {
        client.skillComponents.reduce(home) { $0.appendingPathComponent($1) }
    }

    private func configure(_ client: Client, executable: URL, server: URL) throws {
        let remove: [String]
        let add: [String]
        switch client {
        case .codex:
            remove = ["mcp", "remove", Self.serverName]
            add = ["mcp", "add", Self.serverName, "--", server.path, "--mcp"]
        case .claude:
            remove = ["mcp", "remove", "--scope", "user", Self.serverName]
            add = ["mcp", "add", "--transport", "stdio", "--scope", "user",
                   Self.serverName, "--", server.path, "--mcp"]
        }
        _ = try? run(executable, arguments: remove)
        let result = try run(executable, arguments: add)
        guard result.status == 0 else {
            throw IntegrationError(result.output.isEmpty ? "The agent rejected its MCP configuration." : result.output)
        }
    }

    private func detectedClients() -> [(Client, URL)] {
        Client.allCases.compactMap { client in findExecutable(named: client == .codex ? "codex" : "claude").map { (client, $0) } }
    }

    private func findExecutable(named name: String) -> URL? {
        var candidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map { URL(fileURLWithPath: String($0)).appendingPathComponent(name) }
        candidates += [
            URL(fileURLWithPath: "/opt/homebrew/bin/\(name)"),
            URL(fileURLWithPath: "/usr/local/bin/\(name)"),
            home.appendingPathComponent(".local/bin/\(name)"),
            home.appendingPathComponent(".npm-global/bin/\(name)")
        ]
        return candidates.first(where: { files.isExecutableFile(atPath: $0.path) })
    }

    private func run(_ executable: URL, arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus,
                String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func joined(_ names: [String]) -> String {
        switch names.count {
        case 0: return "no agents"
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }
}

private struct IntegrationError: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
final class AgentIntegrationController: ObservableObject {
    @Published private(set) var isWorking = false
    @Published private(set) var isInstalled = false
    @Published private(set) var hasAnyInstallation = false
    @Published private(set) var status = "Checking local agents…"
    @Published private(set) var detail: String?
    private let integration = AgentIntegration()

    func refresh() {
        guard !isWorking else { return }
        isWorking = true
        Task.detached { [integration] in
            let result = integration.status()
            await MainActor.run {
                self.isWorking = false
                self.isInstalled = result.isComplete
                self.hasAnyInstallation = result.hasAnyInstallation
                if result.detectedClients.isEmpty {
                    self.status = "No supported agents found"
                    self.detail = "Install Claude Code or Codex first."
                } else if result.isComplete {
                    self.status = "Available to \(result.installedClients.joined(separator: " and "))"
                    self.detail = nil
                } else if result.installedClients.isEmpty {
                    self.status = "Not set up"
                    self.detail = "Found \(result.detectedClients.joined(separator: " and "))."
                } else {
                    self.status = "Partly set up"
                    self.detail = "Available to \(result.installedClients.joined(separator: " and "))."
                }
            }
        }
    }

    func install() { perform(installedAfter: true) { try $0.install() } }
    func uninstall() { perform(installedAfter: false) { try $0.uninstall() } }

    private func perform(installedAfter: Bool,
                         _ operation: @escaping @Sendable (AgentIntegration) throws -> AgentIntegrationResult) {
        guard !isWorking else { return }
        isWorking = true
        detail = nil
        Task.detached { [integration] in
            do {
                let result = try operation(integration)
                await MainActor.run {
                    self.isWorking = false
                    self.isInstalled = installedAfter
                    self.hasAnyInstallation = installedAfter
                    self.status = self.isInstalled ? "Agent access installed" : "Agent access removed"
                    self.detail = result.message
                }
            } catch {
                let result = integration.status()
                await MainActor.run {
                    self.isWorking = false
                    self.isInstalled = result.isComplete
                    self.hasAnyInstallation = result.hasAnyInstallation
                    self.status = "Agent access needs attention"
                    self.detail = error.localizedDescription
                }
            }
        }
    }

}
