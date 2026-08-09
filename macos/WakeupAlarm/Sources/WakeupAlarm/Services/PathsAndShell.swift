import Foundation

enum WakeupPaths {
    static var home: URL {
        if let env = ProcessInfo.processInfo.environment["WAKEUP_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        // Package: .../macos/WakeupAlarm -> repo root is two levels up from package dir
        // When run via .app / Launch command, WAKEUP_HOME is set explicitly.
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let candidate = cwd
        if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("wakeup.sh").path) {
            return candidate
        }
        let up1 = cwd.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: up1.appendingPathComponent("wakeup.sh").path) {
            return up1
        }
        let up2 = up1.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: up2.appendingPathComponent("wakeup.sh").path) {
            return up2
        }
        // Fallback: relative to executable (swift run builds into .build)
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var dir = exe.deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("wakeup.sh").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        return cwd
    }

    static var configURL: URL { home.appendingPathComponent("config.json") }
    static var mediaURL: URL { home.appendingPathComponent("media", isDirectory: true) }
    static var wakeupSh: URL { home.appendingPathComponent("wakeup.sh") }
    static var playSh: URL { home.appendingPathComponent("lib/play.sh") }
    static var installSh: URL { home.appendingPathComponent("install.sh") }
    static var uninstallSh: URL { home.appendingPathComponent("uninstall.sh") }
    static var fixturesDir: URL { home.appendingPathComponent("tests/fixtures", isDirectory: true) }

    static var statusURL: URL {
        if let env = ProcessInfo.processInfo.environment["WAKEUP_STATUS"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        let tmp = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: tmp, isDirectory: true).appendingPathComponent("claude-wakeup.status.json")
    }

    static var lockURL: URL {
        if let env = ProcessInfo.processInfo.environment["WAKEUP_LOCK"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        let tmp = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: tmp, isDirectory: true).appendingPathComponent("claude-wakeup.lock", isDirectory: true)
    }

    static var defaultLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/wakeup.log")
    }

    static var globalSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }
}

enum ShellRunner {
    @discardableResult
    static func run(
        _ executable: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        stdin: String? = nil,
        cwd: URL? = nil
    ) -> (exitCode: Int32, stdout: String, stderr: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["WAKEUP_HOME"] = WakeupPaths.home.path
        for (k, v) in environment { env[k] = v }
        proc.environment = env
        if let cwd { proc.currentDirectoryURL = cwd }

        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err

        if let stdin {
            let inp = Pipe()
            proc.standardInput = inp
            if let data = stdin.data(using: .utf8) {
                inp.fileHandleForWriting.write(data)
            }
            try? inp.fileHandleForWriting.close()
        } else {
            proc.standardInput = FileHandle.nullDevice
        }

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return (1, "", error.localizedDescription)
        }

        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (proc.terminationStatus, stdout, stderr)
    }

    static func runDetached(
        _ executable: String,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["WAKEUP_HOME"] = WakeupPaths.home.path
        for (k, v) in environment { env[k] = v }
        proc.environment = env
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
    }
}

enum ConfigStore {
    static func load() -> WakeupConfig {
        let url = WakeupPaths.configURL
        guard let data = try? Data(contentsOf: url) else { return .default }
        let dec = JSONDecoder()
        if let cfg = try? dec.decode(WakeupConfig.self, from: data) {
            return cfg
        }
        return .default
    }

    static func save(_ config: WakeupConfig) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(config)
        let url = WakeupPaths.configURL
        let tmp = url.appendingPathExtension("tmp.\(ProcessInfo.processInfo.processIdentifier)")
        try data.write(to: tmp, options: .atomic)
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: url)
        }
    }
}

enum SystemProbe {
    static func idleSeconds() -> Int {
        let r = ShellRunner.run("/usr/sbin/ioreg", arguments: ["-c", "IOHIDSystem"])
        for line in r.stdout.split(separator: "\n") {
            if line.contains("HIDIdleTime"), let num = line.split(separator: "=").last {
                let digits = num.filter { $0.isNumber }
                if let ns = UInt64(digits) {
                    return Int(ns / 1_000_000_000)
                }
            }
        }
        return 0
    }

    static func claudeSettingsExist(projectPath: String?, scope: String) -> Bool {
        let url: URL
        if scope == "project", let p = projectPath, !p.isEmpty {
            url = URL(fileURLWithPath: p).appendingPathComponent(".claude/settings.json")
        } else {
            url = WakeupPaths.globalSettingsURL
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func hooksInstalled(projectPath: String?, scope: String) -> Bool {
        let url: URL
        if scope == "project", let p = projectPath, !p.isEmpty {
            url = URL(fileURLWithPath: p).appendingPathComponent(".claude/settings.json")
        } else {
            url = WakeupPaths.globalSettingsURL
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return text.contains("wakeup.sh")
    }

    static func which(_ name: String) -> String? {
        let r = ShellRunner.run("/usr/bin/which", arguments: [name])
        let path = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.exitCode == 0 && !path.isEmpty ? path : nil
    }

    static func readStatus() -> EngineStatus {
        guard let data = try? Data(contentsOf: WakeupPaths.statusURL),
              let s = try? JSONDecoder().decode(EngineStatus.self, from: data) else {
            return .idle
        }
        return s
    }

    static func lockHeld() -> Bool {
        let pidFile = WakeupPaths.lockURL.appendingPathComponent("pid")
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return kill(pid, 0) == 0
    }

    static func logURL(for config: WakeupConfig) -> URL {
        if !config.logPath.isEmpty {
            return URL(fileURLWithPath: config.logPath)
        }
        return WakeupPaths.defaultLogURL
    }

    static func readLogTail(_ url: URL, maxLines: Int = 80) -> [LogRow] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).suffix(maxLines)
        return lines.map { line in
            let s = String(line)
            if s.count > 21 {
                let ts = String(s.prefix(19))
                let body = String(s.dropFirst(21))
                return LogRow(line: s, timestamp: ts, body: body)
            }
            return LogRow(line: s, timestamp: "", body: s)
        }
    }

    static func listMedia() -> [URL] {
        let dir = WakeupPaths.mediaURL
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return [] }
        let exts = Set(["mp4", "mov", "mkv", "webm"])
        return files.filter { exts.contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
