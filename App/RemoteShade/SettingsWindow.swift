import AppKit
import SwiftUI
import ServiceManagement

final class ReleaseUpdateChecker: ObservableObject {
    static let repositoryURL = URL(string: "https://github.com/ymh001/remoteshade/releases")!
    @Published var automatic: Bool {
        didSet { defaults.set(automatic, forKey: "githubAutomaticUpdates") }
    }
    @Published private(set) var checking = false
    @Published private(set) var message = ""
    @Published private(set) var downloadURL: URL?
    private let defaults: UserDefaults
    private let session: URLSession
    private let currentVersion: String

    init(defaults: UserDefaults = .standard, session: URLSession = .shared,
         currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0") {
        self.defaults = defaults
        self.session = session
        self.currentVersion = currentVersion
        automatic = defaults.bool(forKey: "githubAutomaticUpdates")
    }

    struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
    }

    static func versionParts(_ version: String) -> [Int]? {
        let value = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == 3 ? numbers : nil
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool? {
        guard let candidate = versionParts(candidate), let current = versionParts(current) else { return nil }
        return current.lexicographicallyPrecedes(candidate)
    }

    func checkIfDue(now: Date = Date()) {
        guard automatic else { return }
        let previous = defaults.object(forKey: "githubLastUpdateAttempt") as? Date ?? .distantPast
        guard now.timeIntervalSince(previous) >= 86400 else { return }
        check()
    }

    func check() {
        guard !checking else { return }
        checking = true
        message = "正在检查 GitHub Releases…"
        downloadURL = nil
        defaults.set(Date(), forKey: "githubLastUpdateAttempt")
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/ymh001/remoteshade/releases/latest")!)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("RemoteShade/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.checking = false
                guard error == nil, let response = response as? HTTPURLResponse else {
                    self.message = "检查失败，请检查网络后重试。"
                    return
                }
                if response.statusCode == 404 {
                    self.message = "GitHub 尚未发布正式版本。"
                    return
                }
                guard response.statusCode == 200, let data = data,
                      let release = try? JSONDecoder().decode(Release.self, from: data),
                      !release.draft, !release.prerelease,
                      let newer = Self.isNewer(release.tag_name, than: self.currentVersion) else {
                    self.message = "暂时无法读取有效版本信息，请稍后重试。"
                    return
                }
                if newer {
                    self.message = "发现新版本 \(release.tag_name)"
                    self.downloadURL = Self.repositoryURL.appendingPathComponent("tag").appendingPathComponent(release.tag_name)
                } else {
                    self.message = "当前已是最新版本（\(self.currentVersion)）。"
                }
            }
        }.resume()
    }
}

final class RemoteShadeWindow: NSWindow {
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "w" {
            close()
        } else { super.keyDown(with: event) }
    }
}

final class RemoteShadeSettingsWindow: NSWindowController, NSWindowDelegate {
    init() {
        let window = RemoteShadeWindow(contentRect: NSRect(x: 0, y: 0, width: 1020, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "RemoteShade 设置"
        // Settings remain visible when another app or the authorization dialog takes focus.
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 900, height: 680)
        window.contentView = NSHostingView(rootView: RemoteShadeSettingsView())
        window.center()
        super.init(window: window)
        window.delegate = self
    }
    override func showWindow(_ sender: Any?) {
        NSApp.setActivationPolicy(.regular)
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class ScreenSharingGuide: NSWindowController {
    static let shared = ScreenSharingGuide()

    private init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 280),
                            styleMask: [.titled, .closable, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = "屏幕共享操作指引"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let content = NSHostingView(rootView: ScreenSharingGuideView {
            ScreenSharingGuide.shared.close()
        })
        panel.contentView = content
        panel.setContentSize(content.fittingSize)
        super.init(window: panel)
    }

    func present() {
        guard let window = window else { return }
        if !window.isVisible, let frame = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: frame.maxX - window.frame.width - 20,
                                          y: frame.minY + 20))
        }
        window.orderFrontRegardless()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private struct ScreenSharingGuideView: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("通用 → 共享").font(.headline)
            Text("在“内容与媒体”中找到“屏幕共享”，点击这一行右侧的开关。")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.on.rectangle").foregroundStyle(.purple)
                    Text("屏幕共享").fontWeight(.medium)
                    Spacer()
                    Image(systemName: "switch.2").font(.title2)
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                }
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.red, lineWidth: 2))
                Text("位置示意 · 实际开关状态以系统设置为准")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("关闭会断开当前屏幕共享连接。右侧 ⓘ 可设置允许访问的用户。")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("可拖动标题栏移动此指引").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("知道了", action: dismiss)
            }
        }.padding(20).frame(width: 360)
    }
}

// Reuse the existing controls and their target/actions without their fixed-size pages.
private struct AccessibilityAppDragItem: View {
    static func itemProvider() -> NSItemProvider {
        NSItemProvider(object: Bundle.main.bundleURL as NSURL)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable().frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("RemoteShade").fontWeight(.medium)
                Text("拖到辅助功能应用列表，然后开启开关")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "hand.draw").foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.4)))
        .contentShape(Rectangle())
        .onDrag { Self.itemProvider() }
        .accessibilityLabel("RemoteShade 应用，拖到系统辅助功能列表以添加授权")
    }
}

final class AccessibilityGuide: NSWindowController {
    static let shared = AccessibilityGuide()
    private var positioningTimer: Timer?

    private init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 120),
                            styleMask: [.titled, .closable, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = "拖入上方辅助功能列表"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: AccessibilityGuideView())
        if let size = panel.contentView?.fittingSize { panel.setContentSize(size) }
        super.init(window: panel)
    }

    static func origin(settings: NSRect, panel: NSSize, visible: NSRect) -> NSPoint {
        NSPoint(x: max(visible.minX, min(settings.midX - panel.width / 2, visible.maxX - panel.width)),
                y: max(visible.minY, min(settings.minY - panel.height - 8, visible.maxY - panel.height)))
    }

    private func positionBelowSettings() {
        guard let window = window else { return }
        var settingsFrame: NSRect?
        if let process = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first,
           let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
           let primary = NSScreen.screens.first {
            for info in windows {
                guard (info[kCGWindowOwnerPID as String] as? Int) == Int(process.processIdentifier),
                      (info[kCGWindowLayer as String] as? Int) == 0,
                      let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                      let rect = CGRect(dictionaryRepresentation: bounds),
                      rect.width > 400, rect.height > 300 else { continue }
                settingsFrame = NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY,
                                       width: rect.width, height: rect.height)
                break
            }
        }
        let screen = NSScreen.screens.first { screen in
            guard let frame = settingsFrame else { return false }
            return screen.frame.contains(NSPoint(x: frame.midX, y: frame.midY))
        } ?? window.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        window.setFrameOrigin(Self.origin(settings: settingsFrame ?? visible,
                                          panel: window.frame.size, visible: visible))
    }

    func present() {
        positionBelowSettings()
        window?.orderFrontRegardless()
        positioningTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self, self.window?.isVisible == true else {
                timer.invalidate()
                return
            }
            self.positionBelowSettings()
        }
        positioningTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    override func close() {
        positioningTimer?.invalidate()
        positioningTimer = nil
        super.close()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private struct AccessibilityGuideView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AccessibilityAppDragItem()
            HStack {
                Text("旧授权无效时，先删除旧条目再拖入。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("完成") {
                    app.mediaKeyTap.refreshPermissions(restart: true)
                    AccessibilityGuide.shared.close()
                }
            }
        }.padding(12).frame(width: 440)
    }
}

private final class SettingsControlHost: NSView {
    let control: NSView

    init(control: NSView) {
        self.control = control
        super.init(frame: .zero)
        control.removeFromSuperview()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: leadingAnchor),
            control.trailingAnchor.constraint(equalTo: trailingAnchor),
            control.centerYAnchor.constraint(equalTo: centerYAnchor),
            control.heightAnchor.constraint(equalTo: heightAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private struct SettingsControl: NSViewRepresentable {
    let control: NSView
    let onChange: () -> Void

    final class Coordinator: NSObject {
        weak var originalTarget: AnyObject?
        var originalAction: Selector?
        var enabledBeforeSuppression: Bool?
        var interactionAllowed = true
        var onChange: () -> Void
        init(onChange: @escaping () -> Void) { self.onChange = onChange }
        @objc func changed(_ sender: NSControl) {
            guard interactionAllowed else { return }
            sender.sendAction(originalAction, to: originalTarget)
            onChange()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }
    func makeNSView(context: Context) -> SettingsControlHost {
        if let input = control as? NSControl {
            input.font = .systemFont(ofSize: NSFont.systemFontSize)
            context.coordinator.originalTarget = input.target
            context.coordinator.originalAction = input.action
            input.target = context.coordinator
            input.action = #selector(Coordinator.changed(_:))
        }
        return SettingsControlHost(control: control)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SettingsControlHost, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 220, height: proposal.height ?? 26)
    }
    func updateNSView(_ view: SettingsControlHost, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.interactionAllowed = context.environment.isEnabled
        if let input = view.control as? NSControl {
            if !context.environment.isEnabled {
                if context.coordinator.enabledBeforeSuppression == nil {
                    context.coordinator.enabledBeforeSuppression = input.isEnabled
                }
                input.isEnabled = false
            } else if let enabled = context.coordinator.enabledBeforeSuppression {
                input.isEnabled = enabled
                context.coordinator.enabledBeforeSuppression = nil
            }
        }
    }
    static func dismantleNSView(_ view: SettingsControlHost, coordinator: Coordinator) {
        if let input = view.control as? NSControl, input.target === coordinator {
            if let enabled = coordinator.enabledBeforeSuppression { input.isEnabled = enabled }
            input.target = coordinator.originalTarget
            input.action = coordinator.originalAction
        }
    }
}

private final class SettingsControls: ObservableObject {
    let keyboard: KeyboardPrefsViewController?
    let advanced: MainPrefsViewController?
    @Published var displays: [DisplaysPrefsCellView] = []
    private var displayObjects: [ObjectIdentifier] = []

    init() {
        keyboard = keyboardPrefsVc
        advanced = mainPrefsVc
        _ = advanced?.view
        _ = keyboard?.view
        _ = displaysPrefsVc?.view
        reloadDisplays()
    }

    func reloadDisplays() {
        let current = DisplayManager.shared.getAllDisplays()
        let identifiers = current.map { ObjectIdentifier($0) }
        guard identifiers != displayObjects else { return }
        displayObjects = identifiers
        guard let controller = displaysPrefsVc else { return }
        controller.displays = current
        displays = current.indices.compactMap { index in
            let cell = controller.tableView(controller.displayList,
                                 viewFor: controller.displayList.tableColumns.first,
                                 row: index) as? DisplaysPrefsCellView
            cell?.settingsPollingField = cell?.pollingCount.controlView
            return cell
        }
    }
}

private struct SettingsCardStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
            configuration.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)))
    }
}

struct RemoteShadeSettingsView: View {
    @State private var selection: String? = "通用"
    @StateObject private var controls = SettingsControls()
    @ObservedObject private var keyboardAccess = app.mediaKeyTap
    @ObservedObject private var releaseUpdates = app.releaseUpdates
    @State private var refresh = 0
    @State private var customSeconds = "15"
    @State private var customError = ""
    @State private var sharingSettingsError = ""
    @State private var permissionSettingsError = ""
    @State private var customMode = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let pages = [("通用", "gearshape"), ("显示器", "display"), ("键盘", "keyboard"), ("远控与锁屏", "lock.display"), ("高级", "slider.horizontal.3"), ("关于", "info.circle")]
    private var remote: RemoteAutomation { app.automation }

    var body: some View {
        let _ = refresh
        return NavigationSplitView {
            List(selection: $selection) {
                ForEach(pages, id: \.0) { title, icon in
                    Label(title, systemImage: icon)
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .contentShape(Rectangle())
                        .tag(title)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selection ?? "通用").font(.system(size: 22, weight: .bold))
                    }
                    .padding(.bottom, 2)
                    content
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .groupBoxStyle(SettingsCardStyle())
        .onReceive(timer) { _ in refresh += 1; controls.reloadDisplays() }
        .onAppear { customSeconds = String(Int(remote.policy.delay)) }

    }

    @ViewBuilder private var content: some View {
        switch selection {
        case "通用": general
        case "远控与锁屏": automation
        case "显示器":
            if RemoteBridge.shared.isProtecting { Label("远控黑屏或恢复期间暂停显示器设置", systemImage: "lock.fill").foregroundStyle(.secondary) }
            displaySettings.disabled(RemoteBridge.shared.isProtecting)
        case "键盘": keyboardSettings
        case "高级":
            advancedSettings.disabled(RemoteBridge.shared.isProtecting)
        default: about
        }
    }

    private func controlRow(_ title: String, _ control: NSView) -> some View {
        HStack(spacing: 20) {
            Text(title).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            SettingsControl(control: control, onChange: { refresh += 1 }).frame(width: 220, height: 26)
                .accessibilityLabel(title)
        }.frame(minHeight: 32)
    }

    private func controlToggle(_ title: String, _ button: NSButton) -> some View {
        settingToggle(title, isOn: Binding(get: { button.state == .on }, set: { value in
            button.state = value ? .on : .off
            button.sendAction(button.action, to: button.target)
            refresh += 1
        })).disabled(!button.isEnabled)
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 12, content: content)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var keyboardSettings: some View {
        VStack(spacing: 16) {
            card("键盘控制权限") {
                HStack {
                    Text("辅助功能")
                    Spacer()
                    Text(keyboardAccess.permissionState.accessibility ? "已授权" : "未授权")
                        .foregroundStyle(keyboardAccess.permissionState.accessibility ? Color.secondary : Color.orange)
                }
                HStack {
                    Text("按键监听")
                    Spacer()
                    Text(keyboardAccess.listening ? "运行中" : "未运行")
                        .foregroundStyle(keyboardAccess.listening ? Color.secondary : Color.orange)
                }
                HStack {
                    Text("最近检测")
                    Spacer()
                    Text(keyboardAccess.lastPermissionCheck, style: .time).foregroundStyle(.secondary)
                }
                if !keyboardAccess.permissionState.canControlKeys {
                    Text("打开辅助功能设置，将下方应用拖入列表并开启开关。如果已有条目但授权无效，请先删除旧条目，再重新拖入。")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    AccessibilityAppDragItem()
                    Button("打开辅助功能设置并显示拖拽指引…") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        if !NSWorkspace.shared.open(url) {
                            permissionSettingsError = "请手动打开“系统设置 → 隐私与安全性 → 辅助功能”。"
                        } else {
                            permissionSettingsError = ""
                            AccessibilityGuide.shared.present()
                        }
                    }
                    if !permissionSettingsError.isEmpty {
                        Text(permissionSettingsError).font(.callout).foregroundStyle(.red)
                    }
                }
                Button("重新检测并启用按键监听") {
                    app.mediaKeyTap.refreshPermissions(restart: true)
                    refresh += 1
                }
                Text("授权状态变化后会自动重新启用监听。权限可用后，可用亮度键验证实际控制效果。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let controller = controls.keyboard {
                card("亮度与对比度") {
                    controlRow("亮度按键", controller.keyboardBrightness)
                    controlRow("控制的显示器", controller.multiKeyboardBrightness)
                    controlToggle("使用精细亮度步进", controller.useFineScale)
                    controlToggle("分别调节硬件与软件亮度", controller.separateCombinedScale)
                    if !controller.rowDisableAltBrightnessKeysCheck.isHidden {
                        controlToggle("禁用替代亮度按键", controller.disableAltBrightnessKeys)
                    }
                    if !controller.rowCustomBrightnessShortcuts.isHidden {
                        Divider()
                        controlRow("提高亮度", controller.customBrightnessUp)
                        controlRow("降低亮度", controller.customBrightnessDown)
                        controlRow("提高对比度", controller.customContrastUp)
                        controlRow("降低对比度", controller.customContrastDown)
                    }
                }
                card("音量") {
                    controlRow("音量按键", controller.keyboardVolume)
                    controlRow("控制的显示器", controller.multiKeyboardVolume)
                    controlToggle("使用精细音量步进", controller.useFineScaleVolume)
                    if !controller.rowCustomAudioShortcuts.isHidden {
                        Divider()
                        controlRow("提高音量", controller.customVolumeUp)
                        controlRow("降低音量", controller.customVolumeDown)
                        controlRow("静音", controller.customMute)
                    }
                }
            }
        }
    }

    private var advancedSettings: some View {
        VStack(spacing: 16) {
            if let controller = controls.advanced {
                card("亮度控制") {
                    controlToggle("组合硬件与软件亮度", controller.combinedBrightness)
                    controlToggle("允许软件亮度降至零", controller.allowZeroSwBrightness)
                    controlToggle("平滑调节亮度", controller.enableSmooth)
                    controlToggle("同步显示器亮度", controller.enableBrightnessSync)
                }
                card("启动行为") {
                    controlRow("启动时的显示器设置", controller.startupAction)
                }
                card("重置") {
                    Button("重置所有设置…") { controller.resetPrefsClicked(NSButton()) }
                }
            }
        }
    }

    private var displaySettings: some View {
        VStack(spacing: 16) {
            if controls.displays.isEmpty {
                ContentUnavailableView("未检测到显示器", systemImage: "display")
            }
            ForEach(controls.displays, id: \.display?.identifier) { cell in
                displayCard(cell)
            }
        }
    }

    private func displayCard(_ cell: DisplaysPrefsCellView) -> some View {
        card(cell.display?.name ?? "显示器") {
            HStack { Text("显示器类型"); Spacer(); Text(cell.displayType.stringValue).foregroundStyle(.secondary) }
            HStack { Text("控制方式"); Spacer(); Text(cell.controlMethod.stringValue).foregroundStyle(.secondary) }
            Divider()
            controlToggle("允许键盘控制", cell.enabledButton)
            controlToggle("使用硬件 DDC 控制", cell.ddcButton)
            controlToggle("隐藏系统音量提示", cell.disableVolumeOSDButton)
            controlToggle("避免修改 Gamma", cell.avoidGamma)
            DisclosureGroup("兼容性与 DDC 参数") {
                VStack(alignment: .leading, spacing: 12) {
                    controlRow("读取亮度和音量", cell.pollingModeMenu)
                    if let count = cell.settingsPollingField { controlRow("自定义读取次数", count) }
                    controlToggle("延长 DDC 通信间隔", cell.longerDelayButton)
                    controlToggle("允许显示器静音", cell.enableMuteButton)
                    controlRow("硬件与软件亮度切换点", cell.combinedBrightnessSwitchingPoint)
                    controlRow("匹配的音频设备名称", cell.audioDeviceNameOverride)
                    Button("使用当前音频设备名称") { cell.updateWithCurrentAudioName(NSButton()) }
                    ddcControls("亮度", enabled: cell.unavailableDDCBrightness, minimum: cell.minDDCOverrideBrightness,
                                maximum: cell.maxDDCOverrideBrightness, curve: cell.curveDDCBrightness,
                                inverted: cell.invertDDCBrightness, remap: cell.remapDDCBrightness)
                    ddcControls("音量", enabled: cell.unavailableDDCVolume, minimum: cell.minDDCOverrideVolume,
                                maximum: cell.maxDDCOverrideVolume, curve: cell.curveDDCVolume,
                                inverted: cell.invertDDCVolume, remap: cell.remapDDCVolume)
                    ddcControls("对比度", enabled: cell.unavailableDDCContrast, minimum: cell.minDDCOverrideContrast,
                                maximum: cell.maxDDCOverrideContrast, curve: cell.curveDDCContrast,
                                inverted: cell.invertDDCContrast, remap: cell.remapDDCContrast)
                    Button("重置此显示器设置") { cell.resetSettings(NSButton()); refresh += 1 }
                }.padding(.top, 12)
            }
        }
    }

    private func ddcControls(_ title: String, enabled: NSButton, minimum: NSTextField,
                             maximum: NSTextField, curve: NSSlider, inverted: NSButton,
                             remap: NSTextField) -> some View {
        DisclosureGroup(title) {
            VStack(spacing: 12) {
                controlToggle("启用 DDC 控制", enabled)
                controlRow("最小值", minimum)
                controlRow("最大值", maximum)
                controlRow("响应曲线", curve)
                controlToggle("反转数值", inverted)
                controlRow("VCP 代码覆盖", remap)
            }.padding(.top, 12)
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("启动与外观") {
                VStack(alignment: .leading, spacing: 18) {
                    settingToggle("开机自启动", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { _ in remote.toggleLogin() }))
                    HStack { Text("菜单栏图标"); Spacer(); Image(nsImage: MenuBarIcon.make()); Text("幕帘").foregroundStyle(.secondary) }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("电源") {
                VStack(alignment: .leading, spacing: 12) {
                    settingToggle("系统自动休眠", isOn: Binding(get: { remote.sleepSettings?.values.allSatisfy { $0 > 0 } ?? false }, set: { _ in remote.toggleSleep() }))
                        .disabled(remote.sleepBusy || remote.sleepSettings == nil)
                    Text(remote.sleepBusy ? "等待系统授权或写入结果…" : "修改需要管理员授权，退出应用后仍然生效。开启时恢复此前时长，无记录时为 10 分钟。")
                        .font(.callout).foregroundStyle(.secondary)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("菜单栏显示") {
                VStack(alignment: .leading, spacing: 12) {
                    preference("显示亮度滑块", key: .hideBrightness, inverted: true)
                    Divider()
                    preference("显示音量滑块", key: .hideVolume, inverted: true)
                    Divider()
                    preference("显示对比度滑块", key: .showContrast)
                    Divider()
                    preference("显示滑块百分比", key: .enableSliderPercent)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.toggleStyle(.switch)
    }

    private var automation: some View {
        VStack(alignment: .leading, spacing: 16) {
            card("系统屏幕共享") {
                HStack {
                    Text("屏幕共享")
                    Spacer()
                    Button("打开设置并查看指引…") {
                        let url = URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension")!
                        if NSWorkspace.shared.open(url) {
                            sharingSettingsError = ""
                            ScreenSharingGuide.shared.present()
                        } else {
                            sharingSettingsError = "无法打开系统设置，请手动前往“系统设置 → 通用 → 共享”。"
                        }
                    }
                }.frame(minHeight: 32)
                Text("请在“系统设置 → 通用 → 共享”中开启或关闭屏幕共享。关闭后，当前屏幕共享连接会断开。")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !sharingSettingsError.isEmpty {
                    Text(sharingSettingsError).font(.callout).foregroundStyle(.red)
                }
            }
            GroupBox("远控隐私") {
                VStack(alignment: .leading, spacing: 12) {
                    settingToggle("远控时黑屏", isOn: Binding(get: { remote.dimOnRemote }, set: { _ in remote.toggleBrightness() }))
                    Text("检测到 Apple 远控连接后，将支持 DDC 的外接屏硬件亮度和 Gamma 设为 0。断开后立即开始恢复。")
                        .font(.callout).foregroundStyle(.secondary)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("断开后的行为") {
                VStack(alignment: .leading, spacing: 12) {
                    settingToggle("远控结束后自动锁屏", isOn: Binding(get: { remote.lockOnDisconnect }, set: { _ in remote.toggleDisconnectLock() }))
                    Text("macOS 自身也可能在远控结束后锁屏。").font(.callout).foregroundStyle(.secondary)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("锁屏后熄屏") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("连续闲置时间", selection: Binding(get: { customMode ? -1 : remote.policy.enabled ? ([15, 30, 60].contains(Int(remote.policy.delay)) ? Int(remote.policy.delay) : -1) : 0 }, set: { value in
                        customMode = value == -1
                        if value == 0 { remote.disableLockSleep() }
                        else if value > 0 { remote.setDelay(value) }
                    })) {
                        Text("关闭").tag(0)
                        Text("15 秒").tag(15)
                        Text("30 秒").tag(30)
                        Text("60 秒").tag(60)
                        Text("自定义").tag(-1)
                    }
                    if customMode || (remote.policy.enabled && ![15, 30, 60].contains(Int(remote.policy.delay))) {
                    HStack {
                        Spacer()
                        TextField("自定义秒数", text: $customSeconds).textFieldStyle(.roundedBorder).frame(width: 95)
                        Text("秒")
                        Button("应用自定义") {
                            guard let seconds = Int(customSeconds), (1...86400).contains(seconds) else { customError = "请输入 1–86400 的整数"; return }
                            customError = ""
                            remote.setDelay(seconds)
                            customMode = true
                        }
                    }
                    }
                    if !customError.isEmpty { Text(customError).foregroundStyle(.red) }
                    Text("键盘或鼠标操作重新计时，解锁后取消计时。显示器唤醒需要时间，延时过短可能刚亮屏就再次熄屏。应用遵循系统默认锁屏与熄屏行为。")
                        .font(.callout).foregroundStyle(.secondary)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.toggleStyle(.switch)
    }

    private func settingToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch)
        }.frame(minHeight: 32)
    }

    private func preference(_ title: String, key: PrefKey, inverted: Bool = false) -> some View {
        settingToggle(title, isOn: Binding(get: { prefs.bool(forKey: key.rawValue) != inverted }, set: { value in
            prefs.set(value != inverted, forKey: key.rawValue)
            app.updateMenusAndKeys()
        }))
    }

    private var about: some View {
        VStack(spacing: 20) {
            Image(nsImage: NSImage(named: NSImage.applicationIconName)!).resizable().frame(width: 128, height: 128)
            Text("RemoteShade").font(.largeTitle.bold())
            Text("显示器调节与远控隐私").foregroundStyle(.secondary)
            Text("1.0.0")
            card("软件更新") {
                settingToggle("自动检查更新", isOn: Binding(get: { releaseUpdates.automatic }, set: { enabled in
                    releaseUpdates.automatic = enabled
                    if enabled { releaseUpdates.checkIfDue() }
                }))
                Text("开启后每天从 GitHub 检查正式版本。发现新版后提供下载入口，由你选择是否安装。")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button(releaseUpdates.checking ? "正在检查…" : "检查更新") { releaseUpdates.check() }
                        .disabled(releaseUpdates.checking)
                    if let url = releaseUpdates.downloadURL {
                        Link("前往 GitHub 下载", destination: url)
                    }
                }
                if !releaseUpdates.message.isEmpty {
                    Text(releaseUpdates.message).font(.callout).foregroundStyle(.secondary)
                }
            }
            GroupBox("开源项目") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("MonitorControl · 显示器控制基础 · MIT")
                    Text("m1ddc · 显示器通信 · MIT")
                    Button("查看开源许可") {
                        if let url = Bundle.main.url(forResource: "OpenSourceLicenses", withExtension: "txt") { NSWorkspace.shared.open(url) }
                    }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(maxWidth: .infinity)
    }
}
