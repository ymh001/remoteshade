import Foundation
import CoreGraphics

protocol GammaControlling {
    var pendingIDs: Set<String> { get }
    func blacken(display: UInt32, uuid: String) throws
    func restore(display: UInt32, uuid: String) throws
    func repairBlackTable(display: UInt32, uuid: String) throws -> Bool
}

final class GammaController: GammaControlling {
    struct Table: Codable {
        let red: [Float]
        let green: [Float]
        let blue: [Float]
        var isBlack: Bool { (red + green + blue).allSatisfy { abs($0) < 0.0001 } }
    }
    private let defaults: UserDefaults
    private var saved: [String: Table]
    private var lastVisible = [String: Table]()
    private let read: (CGDirectDisplayID) throws -> Table
    private let apply: (Table, CGDirectDisplayID) throws -> Void
    var pendingIDs: Set<String> { Set(saved.keys) }

    init(defaults: UserDefaults, read: @escaping (CGDirectDisplayID) throws -> Table = GammaController.readTable,
         apply: @escaping (Table, CGDirectDisplayID) throws -> Void = GammaController.applyTable) {
        self.read = read
        self.apply = apply
        self.defaults = defaults
        saved = defaults.data(forKey: "gammaRecovery").flatMap { try? JSONDecoder().decode([String: Table].self, from: $0) } ?? [:]
    }

    private static func error(_ text: String) -> NSError {
        NSError(domain: "RemoteShade.Gamma", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }

    private func save() throws {
        defaults.set(try JSONEncoder().encode(saved), forKey: "gammaRecovery")
        guard defaults.synchronize() else { throw Self.error("无法保存 Gamma 恢复记录") }
    }

    private static func readTable(_ display: CGDirectDisplayID) throws -> Table {
        let capacity = CGDisplayGammaTableCapacity(display)
        guard capacity > 0, capacity <= 65536 else { throw Self.error("显示器没有可用的 Gamma 表") }
        var red = [Float](repeating: 0, count: Int(capacity))
        var green = red
        var blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &count) == .success, count > 0 else {
            throw Self.error("无法读取 Gamma")
        }
        return Table(red: Array(red.prefix(Int(count))), green: Array(green.prefix(Int(count))), blue: Array(blue.prefix(Int(count))))
    }

    private static func applyTable(_ table: Table, _ display: CGDirectDisplayID) throws {
        guard !table.red.isEmpty, table.red.count == table.green.count, table.red.count == table.blue.count,
              CGSetDisplayTransferByTable(display, UInt32(table.red.count), table.red, table.green, table.blue) == .success else {
            throw Self.error("无法应用 Gamma")
        }
    }

    func blacken(display: UInt32, uuid: String) throws {
        // Periodic verification should not rewrite an already-black table.
        // Reapply only if the system or another app changed it.
        if saved[uuid] != nil, try read(display).isBlack { return }
        if saved[uuid] == nil {
            let current = try read(display)
            guard let visible = current.isBlack ? lastVisible[uuid] : current else {
                throw Self.error("当前 Gamma 已全黑，无法取得可恢复的原值")
            }
            saved[uuid] = visible
        }
        try save()
        let zeros = [Float](repeating: 0, count: saved[uuid]!.red.count)
        try apply(Table(red: zeros, green: zeros, blue: zeros), display)
        let actual = try read(display)
        guard actual.isBlack else {
            throw Self.error("Gamma 被其他调光程序改写")
        }
    }

    func restore(display: UInt32, uuid: String) throws {
        guard let original = saved[uuid] else { return }
        guard !original.isBlack else { throw Self.error("原 Gamma 记录为全黑，无法恢复可见画面") }
        try applyAndVerify(original, display: display)
        lastVisible[uuid] = original
        saved.removeValue(forKey: uuid)
        try save()
    }

    // The lock screen or a display wake may reinstate the blackout after the first readback.
    func repairBlackTable(display: UInt32, uuid: String) throws -> Bool {
        guard let original = lastVisible[uuid], try read(display).isBlack else { return false }
        try applyAndVerify(original, display: display)
        return true
    }

    private func applyAndVerify(_ original: Table, display: UInt32) throws {
        try apply(original, display)
        let actual = try read(display)
        guard actual.red.count == original.red.count,
              zip(actual.red + actual.green + actual.blue, original.red + original.green + original.blue).allSatisfy({ abs($0 - $1) < 0.002 }) else {
            throw Self.error("Gamma 恢复核对失败")
        }
    }
}
