import AppKit
import ServiceManagement
import Darwin
import OSLog

final class RemoteAutomation: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var ready: (() -> Void)?
    var initialized = false
    var policy = DisplayPolicy()
    var monitor: Timer?
    var lockObservers: [NSObjectProtocol] = []
    var reportedLock: Bool?
    var remoteState = RemoteState.unknown
    var automaticRequest = false
    let brightness = BrightnessController()
    let log = Logger(subsystem: "cn.leaflab.display-guard", category: "recovery")
    var recoveryChecks = RecoveryChecks()
    var brightnessBusy = false
    var brightnessTransition = false
    var brightnessDimmed = false
    var lastBrightnessCheck: TimeInterval = -100
    var lastDimRequest = false
    var terminating = false
    var startupRecovery = true
    let brightnessItem = NSMenuItem()
    let brightnessRow = InfoMenuRow(title: "远控时黑屏", explanation: "实现方式\n通过 DDC 将显示器硬件亮度调到 0，并将 Gamma 归零，让实体屏黑屏。远端画面继续正常显示，远控结束后恢复原亮度和 Gamma。")
    let sleepRow = InfoMenuRow(title: "系统自动休眠", explanation: "控制 macOS 系统自动休眠。关闭后，Mac 不会因闲置自动休眠；开启后恢复此前的休眠时长，无记录时默认 10 分钟。修改需要管理员授权，退出应用后仍然生效。远控连接等活动可能暂时阻止休眠。")
    let displayRow = InfoMenuRow(title: "立即熄屏", explanation: "立即让显示器进入休眠。此操作可能导致远端画面黑屏，因此仅在确认没有远控连接时可用。远控期间请使用“远控时黑屏”，让实体屏黑屏并保持远端正常操作。", isToggle: false)
    let loginItem = NSMenuItem(title: "开机自启动", action: #selector(toggleLogin), keyEquivalent: "")
    let disconnectLockItem = NSMenuItem(title: "远控结束后自动锁屏", action: #selector(toggleDisconnectLock), keyEquivalent: "")
    let delayItem = NSMenuItem(title: "锁屏熄屏延时", action: nil, keyEquivalent: "")
    var sessionWasConnected = false
    var lockOnDisconnect = false
    var dimOnRemote = true
    let remoteItem = NSMenuItem(title: "检测远控中…", action: nil, keyEquivalent: "")
    let sleepItem = NSMenuItem(title: "系统自动休眠", action: #selector(toggleSleep), keyEquivalent: "")
    let displayItem = NSMenuItem(title: "立即熄屏", action: #selector(sleepDisplay), keyEquivalent: "")
    let displayStatusRow = StatusMenuRow()
    let remoteStatusRow = StatusMenuRow()
    let stateItem = NSMenuItem(title: "显示器状态待确认", action: nil, keyEquivalent: "")
    let systemSleep = SystemSleepController()
    let sleepQueue = DispatchQueue(label: "cn.leaflab.remoteshade.system-sleep")
    var sleepSettings: [String: Int]?
    var sleepBusy = false
    var sleepReading = false
    var lastSleepRead = Date.distantPast
    var displayProcess: Process?
    var timeout: DispatchWorkItem?
    var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Avoid competing display controllers.
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)
        guard instances.count <= 1 else { NSApp.terminate(nil); return }
        statusItem = app.statusItem
        statusItem.button?.image = MenuBarIcon.make()
        statusItem.button?.toolTip = "RemoteShade"
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        let title = NSMenuItem(title: "RemoteShade 1.0.0", action: nil, keyEquivalent: "")
        menu.addItem(title)
        stateItem.isEnabled = false
        remoteItem.isEnabled = false
        title.isEnabled = false
        stateItem.view = displayStatusRow
        remoteItem.view = remoteStatusRow
        menu.addItem(remoteItem)
        menu.addItem(stateItem)
        menu.addItem(.separator())
        sleepItem.target = self
        displayItem.target = self
        sleepRow.onToggle = { [weak self] in self?.toggleSleep() }
        displayRow.onToggle = { [weak self] in self?.sleepDisplay() }
        sleepItem.view = sleepRow
        displayItem.view = displayRow
        menu.addItem(sleepItem)
        menu.addItem(displayItem)
        brightnessItem.target = self
        menu.addItem(brightnessItem)
        menu.addItem(delayItem)
        disconnectLockItem.target = self
        menu.addItem(disconnectLockItem)
        configureBrightnessRow()
        configureDelayMenu()
        menu.addItem(.separator())
        let help = NSMenuItem(title: "使用说明…", action: #selector(showHelp), keyEquivalent: "")
        help.target = self
        menu.addItem(help)
        let quit = NSMenuItem(title: "退出 RemoteShade", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.addItem(.separator())
        loginItem.target = self
        menu.addItem(loginItem)
        for item in [remoteItem, stateItem, brightnessItem, displayItem] { menu.removeItem(item) }
        initialized = true
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.policy.displayDidSleep()
            self?.stateItem.title = "系统报告显示器已休眠"
        })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.displayWoke()
            self?.stateItem.title = "系统报告显示器已唤醒"
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.displayWoke()
        })
        // Old assertion preference must not silently overwrite system settings.
        reloadSystemSleep()
        UserDefaults.standard.register(defaults: ["automaticDisplaySleep": true, "dimOnRemote": true])
        dimOnRemote = UserDefaults.standard.bool(forKey: "dimOnRemote")
        policy.enabled = UserDefaults.standard.bool(forKey: "automaticDisplaySleep")
        let preferences = UserDefaults.standard
        var savedDelay = preferences.integer(forKey: "lockSleepDelay")
        if !preferences.bool(forKey: "longSleepPresetsMigrated") {
            if [1, 3, 5, 10].contains(savedDelay) {
                savedDelay = 15
                preferences.set(savedDelay, forKey: "lockSleepDelay")
            }
            preferences.set(true, forKey: "longSleepPresetsMigrated")
        }
        policy.delay = (1...86400).contains(savedDelay) ? Double(savedDelay) : 15
        lockOnDisconnect = UserDefaults.standard.bool(forKey: "lockOnDisconnect")
        let distributed = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            lockObservers.append(distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.reportedLock = locked
                self?.tick()
            })
        }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        monitor = timer
        tick()
        refresh()
    }

    func displayWoke() {
        policy.displayDidWake(now: ProcessInfo.processInfo.systemUptime)
        recoveryChecks.schedule(now: ProcessInfo.processInfo.systemUptime)
    }

    func tick() {
        if Date().timeIntervalSince(lastSleepRead) >= 5 { reloadSystemSleep() }
        guard !terminating else { return }
        let observed = SessionProbe.remoteState()
        if observed != remoteState { log.notice("Remote state: \(observed.rawValue, privacy: .public)") }
        remoteState = observed
        if remoteState == .connected { sessionWasConnected = true }
        if remoteState == .disconnected && sessionWasConnected {
            sessionWasConnected = false
            if lockOnDisconnect { lockScreen() }
        }
        let locked = SessionProbe.locked(lastNotification: reportedLock) ?? reportedLock
        let now = ProcessInfo.processInfo.systemUptime
        if remoteState == .connected { policy.clearLockSession() }
        else { policy.observeLock(locked, now: now) }
        let connected = remoteState == .connected || (remoteState == .unknown && sessionWasConnected && lastDimRequest)
        let dim = dimOnRemote && connected && !startupRecovery
        if recoveryChecks.watching && remoteState == .disconnected && locked == true {
            _ = recoveryChecks.observeInput(SessionProbe.localInputCount(), now: now)
        }
        let verify = !brightnessBusy && !dim && recoveryChecks.shouldVerify(
            now: now, locked: locked, remote: remoteState, blackoutEnabled: dimOnRemote
        ) && !SessionProbe.displaysAsleep()
        let periodic = now - lastBrightnessCheck >= 5 && (dim || brightnessDimmed)
        if !brightnessBusy && (verify || startupRecovery || dim != lastDimRequest || periodic) {
            let restoring = !dim && (lastDimRequest || startupRecovery)
            if dim || restoring { recoveryChecks.beginBlackout() }
            if verify { recoveryChecks.consume(now: now) }
            let newBlackout = dim && !lastDimRequest
            RemoteBridge.shared.protect(true)
            brightnessTransition = newBlackout || restoring
            brightnessBusy = true
            lastDimRequest = dim
            lastBrightnessCheck = now
            brightness.update(dim: dim, newBlackout: newBlackout, verifyRestored: verify) { [weak self] message, pending in
                guard let self = self else { return }
                self.brightnessBusy = false
                self.brightnessTransition = false
                if restoring { self.recoveryChecks.schedule(now: ProcessInfo.processInfo.systemUptime) }
                if verify || restoring || (!dim && pending) {
                    self.log.notice("Display update dim=\(dim) verify=\(verify) pending=\(pending): \(message, privacy: .public)")
                }
                self.brightnessDimmed = pending
                let wasStartup = self.startupRecovery
                self.startupRecovery = false
                RemoteBridge.shared.protect(dim || pending)
                if wasStartup { self.ready?(); self.ready = nil }
                RemoteBridge.shared.refreshControls()
                self.stateItem.title = message
                self.tick()
            }
        }
        // Remote capture stays active. System display sleep is only for a locked local session.
        if remoteState == .disconnected && !brightnessBusy && !brightnessDimmed && displayProcess == nil &&
            policy.evaluate(now: now, remote: .disconnected, locked: locked, asleep: SessionProbe.displaysAsleep(), idleSeconds: SessionProbe.localIdleSeconds()) {
            automaticRequest = true
            sleepDisplay()
        }
        remoteItem.title = remoteState.rawValue + (locked == true ? " · 已锁屏" : "")
        if policy.blocked { stateItem.title = "自动熄屏请求失败，请重新选择熄屏设置重试" }
        refresh()
    }

    @objc func toggleBrightness() {
        dimOnRemote.toggle()
        UserDefaults.standard.set(dimOnRemote, forKey: "dimOnRemote")
        tick()
    }

    func menuWillOpen(_ menu: NSMenu) { reloadSystemSleep() }

    func menuDidClose(_ menu: NSMenu) {
        for row in [brightnessRow, sleepRow, displayRow] { row.dismissExplanation() }
    }

    func configureBrightnessRow() {
        brightnessRow.onToggle = { [weak self] in self?.toggleBrightness() }
        brightnessItem.view = brightnessRow
    }

    func configureDelayMenu() {
        let submenu = NSMenu()
        let off = NSMenuItem(title: "关闭", action: #selector(disableLockSleep), keyEquivalent: "")
        off.tag = 0
        off.target = self
        submenu.addItem(off)
        submenu.addItem(.separator())
        for seconds in [15, 30, 60] {
            let item = NSMenuItem(title: "\(seconds) 秒", action: #selector(selectDelay(_:)), keyEquivalent: "")
            item.tag = seconds
            item.target = self
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let custom = NSMenuItem(title: "自定义…秒", action: #selector(customDelay), keyEquivalent: "")
        custom.target = self
        custom.tag = -1
        submenu.addItem(custom)
        delayItem.submenu = submenu
    }

    @objc func disableLockSleep() {
        policy.enabled = false
        policy.lockedSince = nil
        policy.reset()
        UserDefaults.standard.set(false, forKey: "automaticDisplaySleep")
        tick()
    }

    func setDelay(_ seconds: Int) {
        policy.enabled = true
        UserDefaults.standard.set(true, forKey: "automaticDisplaySleep")
        policy.delay = Double(seconds)
        policy.lockedSince = nil
        policy.reset()
        UserDefaults.standard.set(seconds, forKey: "lockSleepDelay")
        tick()
    }

    @objc func selectDelay(_ sender: NSMenuItem) { setDelay(sender.tag) }

    @objc func customDelay() {
        let alert = NSAlert()
        alert.messageText = "自定义锁屏熄屏延时"
        alert.informativeText = "请输入 1–86400 之间的整数秒。"
        let input = NSTextField(string: String(Int(policy.delay)))
        input.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = input
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let value = Int(input.stringValue.trimmingCharacters(in: .whitespaces)), (1...86400).contains(value) else {
            showError("延时必须是 1–86400 之间的整数秒。")
            return
        }
        setDelay(value)
    }

    @objc func toggleDisconnectLock() {
        lockOnDisconnect.toggle()
        log.notice("Lock on disconnect enabled: \(self.lockOnDisconnect)")
        UserDefaults.standard.set(lockOnDisconnect, forKey: "lockOnDisconnect")
        refresh()
    }

    func lockScreen() {
        log.notice("Requesting lock after remote disconnect")
        // The system login framework provides the same immediate lock operation as the UI.
        guard let library = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY) else {
            showError("无法加载系统锁屏接口。")
            return
        }
        defer { dlclose(library) }
        guard let symbol = dlsym(library, "SACLockScreenImmediate") else {
            showError("当前系统未提供即时锁屏接口。")
            return
        }
        let lock = unsafeBitCast(symbol, to: (@convention(c) () -> Int32).self)
        if lock() != 0 { showError("系统锁屏请求失败。") }
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch { showError("无法更新自启动设置：" + error.localizedDescription) }
        refresh()
    }

    func refresh() {
        let lockSuffix = remoteItem.title.contains("已锁屏") ? " · 已锁屏" : ""
        switch remoteState {
        case .connected: remoteStatusRow.update(text: "远控已连接" + lockSuffix, color: .systemGreen)
        case .disconnected: remoteStatusRow.update(text: "无远控连接" + lockSuffix, color: .secondaryLabelColor)
        case .unknown: remoteStatusRow.update(text: "远控检测不可用", color: .systemRed)
        }
        let message = stateItem.title
        let statusText: String
        let statusColor: NSColor
        if message.contains("失败") || message.contains("异常") || message.contains("超时") {
            statusText = message.contains("亮度") ? "显示控制异常" : "熄屏操作失败"
            statusColor = .systemRed
        } else if brightnessBusy && brightnessTransition {
            statusText = lastDimRequest ? "正在关闭实体屏显示…" : "正在恢复显示…"
            statusColor = .systemOrange
        } else if message.contains("DDC 0 + Gamma 0") {
            statusText = "实体屏已黑屏"
            statusColor = .systemPurple
        } else if message.contains("已恢复") {
            statusText = "显示已恢复"
            statusColor = .systemGreen
        } else if message.contains("已休眠") {
            statusText = "显示器已熄屏"
            statusColor = .systemPurple
        } else if message.contains("已唤醒") {
            statusText = "显示器已唤醒"
            statusColor = .systemGreen
        } else {
            statusText = message
            statusColor = .systemOrange
        }
        displayStatusRow.update(text: statusText, color: statusColor, detail: message)

        RemoteBridge.shared.refreshControls()
        brightnessRow.checked = dimOnRemote
        delayItem.title = policy.enabled ? "锁屏后熄屏（\(Int(policy.delay)) 秒）" : "锁屏后熄屏（关闭）"
        for item in delayItem.submenu?.items ?? [] {
            let selected = policy.enabled
                ? item.tag == Int(policy.delay) || item.tag == -1 && ![15, 30, 60].contains(Int(policy.delay))
                : item.tag == 0 && !item.isSeparatorItem
            item.state = selected ? .on : .off
            if item.tag == -1 { item.title = [15, 30, 60].contains(Int(policy.delay)) ? "自定义…秒" : "自定义（\(Int(policy.delay)) 秒）…" }
        }
        disconnectLockItem.state = lockOnDisconnect ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        loginItem.title = SMAppService.mainApp.status == .requiresApproval ? "开机自启动（等待系统批准）" : "开机自启动"
        let values = sleepSettings.map { Array($0.values) } ?? []
        sleepItem.state = values.isEmpty || values.allSatisfy { $0 == 0 } ? .off : (values.allSatisfy { $0 > 0 } ? .on : .mixed)
        sleepItem.title = sleepBusy ? "系统自动休眠（处理中…）" : (sleepSettings == nil ? "系统自动休眠（读取失败）" : "系统自动休眠")
        sleepItem.isEnabled = !sleepBusy && sleepSettings != nil
        sleepRow.title = sleepItem.title
        sleepRow.checked = sleepItem.state == .on
        sleepRow.mixed = sleepItem.state == .mixed
        sleepRow.enabled = sleepItem.isEnabled
        statusItem.button?.toolTip = "RemoteShade"
    }

    func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "操作未完成"
        alert.informativeText = message
        alert.runModal()
    }

    func reloadSystemSleep() {
        guard !sleepBusy && !sleepReading else { return }
        sleepReading = true
        lastSleepRead = Date()
        sleepQueue.async { [weak self] in
            guard let self = self else { return }
            let settings = try? self.systemSleep.read()
            DispatchQueue.main.async {
                self.sleepReading = false
                // A queued user change owns the UI until its verified result arrives.
                guard !self.sleepBusy else { return }
                self.sleepSettings = settings
                self.refresh()
            }
        }
    }

    @objc func toggleSleep() {
        guard !sleepBusy, let settings = sleepSettings else { return }
        let settingsWindow = NSApp.keyWindow as? RemoteShadeWindow
        let enabled = !settings.values.allSatisfy { $0 > 0 }
        sleepBusy = true
        refresh()
        sleepQueue.async { [weak self] in
            guard let self = self else { return }
            var failure: String?
            do { _ = try self.systemSleep.setEnabled(enabled) }
            catch { failure = error.localizedDescription }
            let actual = try? self.systemSleep.read()
            DispatchQueue.main.async {
                self.sleepSettings = actual
                self.sleepBusy = false
                self.lastSleepRead = Date()
                self.refresh()
                // Return to the initiating settings window after authorization, unless
                // the user closed or minimized it while the operation was in progress.
                if let window = settingsWindow, window.isVisible, !window.isMiniaturized {
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                }
                if let failure = failure { self.showError(failure) }
            }
        }
    }

    @objc func sleepDisplay() {
        guard displayProcess == nil else { return }
        if remoteState != .disconnected && !automaticRequest {
            showError("当前存在远控连接或检测状态未知。系统熄屏会影响远端画面，请使用远控硬件调暗开关。")
            return
        }
        let isAutomatic = automaticRequest
        automaticRequest = false
        if isAutomatic {
            // Recheck at dispatch to catch input/unlock/remote changes after policy evaluation.
            guard SessionProbe.remoteState() == .disconnected,
                  SessionProbe.locked(lastNotification: reportedLock) == true,
                  let idle = SessionProbe.localIdleSeconds(), idle >= policy.delay else {
                policy.reset()
                return
            }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        displayItem.isEnabled = false
        displayRow.enabled = false
        stateItem.title = "正在请求熄屏…"
        displayProcess = process
        process.terminationHandler = { [weak self] completed in
            DispatchQueue.main.async {
                guard let self = self, self.displayProcess === completed else { return }
                self.timeout?.cancel()
                self.timeout = nil
                self.displayProcess = nil
                self.displayItem.isEnabled = true
                self.displayRow.enabled = true
                if completed.terminationStatus != 0 {
                    self.stateItem.title = "熄屏请求失败"
                    self.policy.blocked = isAutomatic
                    if !isAutomatic { self.showError("系统未接受熄屏请求，退出码 \(completed.terminationStatus)。") }
                } else if self.stateItem.title == "正在请求熄屏…" {
                    self.stateItem.title = "已发送熄屏请求"
                }
            }
        }
        do {
            try process.run()
            let work = DispatchWorkItem { [weak self, weak process] in
                guard let self = self, let process = process, self.displayProcess === process else { return }
                if process.isRunning { process.terminate() }
                self.stateItem.title = "熄屏请求超时"
            }
            timeout = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
        } catch {
            displayProcess = nil
            displayItem.isEnabled = true
            displayRow.enabled = true
            stateItem.title = "熄屏请求失败"
            policy.blocked = isAutomatic
            if !isAutomatic { showError(error.localizedDescription) }
        }
    }

    @objc func showHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "RemoteShade 1.0.0"
        alert.informativeText = "“系统自动休眠”直接修改 macOS 的自动休眠设置，需要管理员授权。关闭设为永不自动休眠；开启恢复此前时长，无记录时为 10 分钟。退出应用后仍然生效，系统或其他应用仍可能暂时阻止休眠。\n\n远控时将 DDC 硬件亮度和 Gamma 同时设为 0，使实体显示画面黑屏，远端继续显示。断开远控、关闭黑屏开关或退出时恢复原亮度和 Gamma。若你手动调整过硬件亮度，恢复时保留新值。\n\n没有远控且锁屏后，按菜单选择的延时请求系统熄屏。锁屏亮屏时，连续无键盘或鼠标操作达到所选时长才熄屏。任何输入都会重新计时，解锁后取消计时。熄屏延时从唤醒或最后一次键盘、鼠标操作开始计算。显示器从休眠恢复到显示画面需要一定时间，延时过短可能导致画面刚亮起就再次熄屏，因此预设提供 15、30、60 秒。可根据显示器的唤醒速度自定义时长。开启“远控结束后自动锁屏”后，断开会立即请求锁屏，再执行所选熄屏延时。macOS 自身也可能在远控结束后锁屏或熄屏，应用遵循系统默认行为。自启动在登录此账号后运行。远控检测已在本机 Apple 屏幕共享实测，其他模式仍需验证。\n\n显示器拔插或异常退出后，应用会保留按显示器标识保存的亮度恢复记录，下次运行时重试恢复。"
        alert.runModal()
    }

    @objc func quit() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        monitor?.invalidate()
        RemoteBridge.shared.protect(true)
        brightness.update(dim: false) { [weak self] message, pending in
            guard let self = self else { return }
            if pending {
                let alert = NSAlert()
                alert.messageText = "部分显示器亮度尚未恢复"
                alert.informativeText = message + "。恢复记录已保留，下次启动会重试。"
                alert.addButton(withTitle: "保留记录并退出")
                alert.addButton(withTitle: "取消退出")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertSecondButtonReturn {
                    self.terminating = false
                    let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
                    self.monitor = timer
                    RunLoop.main.add(timer, forMode: .common)
                    NSApp.reply(toApplicationShouldTerminate: false)
                    return
                }
            }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.invalidate()
        for observer in lockObservers { DistributedNotificationCenter.default().removeObserver(observer) }
        timeout?.cancel()
        if let process = displayProcess, process.isRunning { process.terminate() }
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
