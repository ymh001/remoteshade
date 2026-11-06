import Foundation
import Darwin

/// All DDC work and recovery records are serialized on this queue.
final class BrightnessController {
    private let queue = DispatchQueue(label: "cn.leaflab.display-guard.ddc")
    private let defaults: UserDefaults
    private var originals: [String: Int]
    private var recentlyRestored = [String: Int]()
    private let helper: URL
    private let gamma: GammaControlling
    private struct DisplayTarget: Decodable {
        let uuid: String
        let id: UInt32
    }

    init(defaults: UserDefaults = .standard, helper: URL? = nil, gamma: GammaControlling? = nil) {
        self.defaults = defaults
        self.gamma = gamma ?? GammaController(defaults: defaults)
        originals = defaults.dictionary(forKey: "brightnessRecovery") as? [String: Int] ?? [:]
        self.helper = helper ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/remoteshade-ddc")
    }

    private func save() throws {
        defaults.set(originals, forKey: "brightnessRecovery")
        guard defaults.synchronize() else { throw failure("无法保存亮度恢复记录") }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "RemoteShade", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func command(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = helper
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        if finished.wait(timeout: .now() + 5) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
            throw failure("显示器通信超时")
        }
        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else { throw failure("显示器不支持控制或已断开") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func read(_ id: String) throws -> Int {
        let result = try command(["display", id, "get", "luminance"])
        guard let value = Int(result), (0...65535).contains(value) else { throw failure("亮度读回无效") }
        return value
    }

    private func write(_ id: String, _ value: Int) throws {
        _ = try command(["display", id, "set", "luminance", String(value)])
        guard try read(id) == value else { throw failure("显示器未接受亮度设置") }
    }

    private func connectedDisplays() throws -> [DisplayTarget] {
        let listing = try command(["display", "list-json"])
        let targets = try JSONDecoder().decode([DisplayTarget].self, from: Data(listing.utf8))
        guard !targets.isEmpty, targets.allSatisfy({ UUID(uuidString: $0.uuid) != nil }) else {
            throw failure("未找到可控制的外接屏")
        }
        return targets
    }

    func update(dim: Bool, newBlackout: Bool = false, verifyRestored: Bool = false, completion: @escaping (String, Bool) -> Void) {
        queue.async {
            var errors: [String] = []
            var count = 0
            var repaired = Set<String>()
            if newBlackout { self.recentlyRestored.removeAll() }
            if dim {
                do {
                    for target in try self.connectedDisplays() {
                        let id = target.uuid
                        do {
                            let current = try self.read(id)
                            if self.originals[id] == nil {
                                self.originals[id] = current
                            }
                            try self.save() // Persist before every hardware write, including retries.
                            if current != 0 { try self.write(id, 0) }
                            try self.gamma.blacken(display: target.id, uuid: id)
                            count += 1
                        } catch { errors.append(error.localizedDescription) }
                    }
                } catch { errors.append(error.localizedDescription) }
            } else {
                var ids = Set(self.originals.keys).union(self.gamma.pendingIDs)
                if verifyRestored { ids.formUnion(self.recentlyRestored.keys) }
                do {
                    let targets = ids.isEmpty ? [] : try self.connectedDisplays()
                    for id in ids {
                        do {
                            guard let target = targets.first(where: { $0.uuid == id }) else {
                                throw self.failure("待恢复显示器已断开")
                            }
                            do {
                                if self.gamma.pendingIDs.contains(id) {
                                    try self.gamma.restore(display: target.id, uuid: id)
                                } else if verifyRestored {
                                    if try self.gamma.repairBlackTable(display: target.id, uuid: id) { repaired.insert("Gamma") }
                                }
                            } catch { errors.append(error.localizedDescription) }
                            // A Gamma error must not prevent hardware brightness recovery.
                            if let original = self.originals[id] ?? self.recentlyRestored[id] {
                                let current = try self.read(id)
                                if current == 0 && original != 0 {
                                    try self.write(id, original)
                                    if verifyRestored { repaired.insert("DDC") }
                                }
                                self.recentlyRestored[id] = current == 0 ? original : current
                                if self.originals.removeValue(forKey: id) != nil { try self.save() }
                            }
                            count += 1
                        } catch { errors.append(error.localizedDescription) }
                    }
                } catch { errors.append(error.localizedDescription) }
            }
            let pending = !self.originals.isEmpty || !self.gamma.pendingIDs.isEmpty
            let message: String
            if let error = errors.first { message = "亮度控制异常 · " + error }
            else if dim { message = "已将 \(count) 台显示器设为 DDC 0 + Gamma 0" }
            else if !repaired.isEmpty { message = "复查发现归零并已恢复：" + repaired.sorted().joined(separator: "、") }
            else { message = "原亮度及 Gamma 已恢复" }
            DispatchQueue.main.async { completion(message, pending) }
        }
    }
}
