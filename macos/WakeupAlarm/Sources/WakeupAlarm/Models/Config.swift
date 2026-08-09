import Foundation

struct WakeupConfig: Codable, Equatable {
    var enabled: Bool
    var delaySecs: Int
    var idleSecs: Int
    var returnSecs: Int
    var maxSecs: Int
    var loop: Bool
    var events: [String]
    var video: String
    var videoMode: String
    var player: String
    var volume: Int?
    var logPath: String
    var ui: UISettings

    struct UISettings: Codable, Equatable {
        var firstRunCompleted: Bool
        var minimizeToTray: Bool
        var startAtLogin: Bool
        var scope: String
        var projectPath: String

        enum CodingKeys: String, CodingKey {
            case firstRunCompleted, minimizeToTray, startAtLogin, scope, projectPath
            case startWithWindows
        }

        init(
            firstRunCompleted: Bool = false,
            minimizeToTray: Bool = true,
            startAtLogin: Bool = false,
            scope: String = "global",
            projectPath: String = ""
        ) {
            self.firstRunCompleted = firstRunCompleted
            self.minimizeToTray = minimizeToTray
            self.startAtLogin = startAtLogin
            self.scope = scope
            self.projectPath = projectPath
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            firstRunCompleted = try c.decodeIfPresent(Bool.self, forKey: .firstRunCompleted) ?? false
            minimizeToTray = try c.decodeIfPresent(Bool.self, forKey: .minimizeToTray) ?? true
            if let v = try c.decodeIfPresent(Bool.self, forKey: .startAtLogin) {
                startAtLogin = v
            } else {
                startAtLogin = try c.decodeIfPresent(Bool.self, forKey: .startWithWindows) ?? false
            }
            scope = try c.decodeIfPresent(String.self, forKey: .scope) ?? "global"
            projectPath = try c.decodeIfPresent(String.self, forKey: .projectPath) ?? ""
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(firstRunCompleted, forKey: .firstRunCompleted)
            try c.encode(minimizeToTray, forKey: .minimizeToTray)
            try c.encode(startAtLogin, forKey: .startAtLogin)
            try c.encode(scope, forKey: .scope)
            try c.encode(projectPath, forKey: .projectPath)
        }
    }

    static let allEvents = [
        "permission_prompt",
        "idle_prompt",
        "agent_needs_input",
        "agent_completed",
        "stop"
    ]

    static var `default`: WakeupConfig {
        WakeupConfig(
            enabled: true,
            delaySecs: 10,
            idleSecs: 15,
            returnSecs: 2,
            maxSecs: 120,
            loop: false,
            events: allEvents,
            video: "",
            videoMode: "random",
            player: "auto",
            volume: nil,
            logPath: "",
            ui: UISettings()
        )
    }
}

struct EngineStatus: Codable {
    var state: String
    var trigger: String
    var video: String
    var idleSecs: Int
    var message: String
    var pid: Int
    var updatedAt: String

    static var idle: EngineStatus {
        EngineStatus(state: "idle", trigger: "", video: "", idleSecs: 0, message: "", pid: 0, updatedAt: "")
    }
}

struct LogRow: Identifiable, Equatable {
    let id = UUID()
    let line: String
    let timestamp: String
    let body: String
}
