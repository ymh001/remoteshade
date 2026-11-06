import Foundation

/// Changes persistent macOS idle-sleep timers, never display sleep or wake settings.
final class SystemSleepController {
    typealias Runner = (String, [String]) throws -> String
    enum Failure: LocalizedError {
        case invalidSettings, command(String), verification
        var errorDescription: String? {
            switch self {
            case .invalidSettings: return "无法读取系统自动休眠设置。"
            case .command(let message): return message
            case .verification: return "系统休眠设置读回不一致，请重新打开菜单检查。"
            }
        }
    }
    static let flags = ["AC Power": "-c", "Battery Power": "-b", "UPS Power": "-u"]
    private let defaults: UserDefaults
    private let runner: Runner
    init(defaults: UserDefaults = .standard, runner: @escaping Runner = SystemSleepController.run) {
        self.defaults = defaults
        self.runner = runner
    }
    static func parse(_ text: String) throws -> [String: Int] {
        var profile: String?
        var result: [String: Int] = [:]
        for line in text.components(separatedBy: .newlines) {
            let value = line.trimmingCharacters(in: .whitespaces)
            if value.hasSuffix(":") {
                let name = String(value.dropLast())
                profile = flags[name] == nil ? nil : name
            } else {
                let fields = value.split(whereSeparator: { $0.isWhitespace })
                if fields.first == "sleep", let profile = profile {
                    guard fields.count == 2, let minutes = Int(fields[1]), (0...Int(Int32.max)).contains(minutes) else {
                        throw Failure.invalidSettings
                    }
                    result[profile] = minutes
                }
            }
        }
        guard !result.isEmpty else { throw Failure.invalidSettings }
        return result
    }
    func read() throws -> [String: Int] {
        try Self.parse(runner("/usr/bin/pmset", ["-g", "custom"]))
    }
    func setEnabled(_ enabled: Bool) throws -> [String: Int] {
        let before = try read()
        var saved = defaults.dictionary(forKey: "systemSleepRestoreMinutes") as? [String: Int] ?? [:]
        for (source, minutes) in before where minutes > 0 { saved[source] = minutes }
        // Save before authorization/write so recovery survives interruption or partial failure.
        defaults.set(saved, forKey: "systemSleepRestoreMinutes")
        defaults.synchronize()
        var expected: [String: Int] = [:]
        var commands: [String] = []
        for source in before.keys.sorted() {
            let previous = saved[source] ?? 10
            let minutes = enabled ? ((1...Int(Int32.max)).contains(previous) ? previous : 10) : 0
            expected[source] = minutes
            if before[source] != minutes {
                // Only whitelisted flags and bounded integers enter this shell command.
                commands.append("/usr/bin/pmset \(Self.flags[source]!) sleep \(minutes)")
            }
        }
        if !commands.isEmpty {
            let command = commands.joined(separator: " && ")
            _ = try runner("/usr/bin/osascript", ["-e", "do shell script \"\(command)\" with administrator privileges"])
        }
        let after = try read()
        guard after == expected else { throw Failure.verification }
        return after
    }
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw Failure.command(output.contains("-128") ? "已取消授权，未完成休眠设置更改。" : "系统休眠设置操作失败：" + output)
        }
        return output
    }
}
