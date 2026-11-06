//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import AppKit
import os.log

class MenuHandler: NSMenu, NSMenuDelegate {
  var combinedSliderHandler: [Command: SliderHandler] = [:]

  var lastMenuRelevantDisplayId: CGDirectDisplayID = 0

  func clearMenu() {
    var items: [NSMenuItem] = []
    for i in 0 ..< self.items.count {
      items.append(self.items[i])
    }
    for item in items {
      self.removeItem(item)
    }
    self.combinedSliderHandler.removeAll()
  }

  func menuWillOpen(_: NSMenu) {
    app.automation.reloadSystemSleep()
    RemoteBridge.shared.refreshControls()
    self.updateMenuRelevantDisplay()
    app.keyboardShortcuts.disengage()
  }

  func menuDidClose(_ menu: NSMenu) { app.automation.menuDidClose(menu) }

  func closeMenu() {
    self.cancelTrackingWithoutAnimation()
  }

  func updateMenus(dontClose: Bool = false) {
    os_log("Menu update initiated", type: .info)
    if !dontClose {
      self.cancelTrackingWithoutAnimation()
    }
    let menuIconPref = prefs.integer(forKey: PrefKey.menuIcon.rawValue)
    var showIcon = false
    if menuIconPref == MenuIcon.show.rawValue {
      showIcon = true
    } else if menuIconPref == MenuIcon.externalOnly.rawValue {
      let externalDisplays = DisplayManager.shared.displays.filter {
        CGDisplayIsBuiltin($0.identifier) == 0
      }
      if externalDisplays.count > 0 {
        showIcon = true
      }
    }
    app.updateStatusItemVisibility(showIcon)
    self.clearMenu()
    let currentDisplay = DisplayManager.shared.getCurrentDisplay()
    var displays: [Display] = []
    if !prefs.bool(forKey: PrefKey.hideAppleFromMenu.rawValue) {
      displays.append(contentsOf: DisplayManager.shared.getAppleDisplays())
    }
    displays.append(contentsOf: DisplayManager.shared.getOtherDisplays())
    displays = DisplayManager.shared.sortDisplaysByFriendlyName()
    let relevant = prefs.integer(forKey: PrefKey.multiSliders.rawValue) == MultiSliders.relevant.rawValue
    let combine = prefs.integer(forKey: PrefKey.multiSliders.rawValue) == MultiSliders.combine.rawValue
    let numOfDisplays = displays.filter { !$0.isDummy }.count
    if numOfDisplays != 0 {
      let asSubMenu: Bool = (displays.count > 3 && !relevant && !combine && app.macOS10()) ? true : false
      var iterator = 0
      for display in displays where (!relevant || DisplayManager.resolveEffectiveDisplayID(display.identifier) == DisplayManager.resolveEffectiveDisplayID(currentDisplay!.identifier)) && !display.isDummy {
        iterator += 1
        if !relevant, !combine, iterator != 1, app.macOS10() {
          self.insertItem(NSMenuItem.separator(), at: 0)
        }
        self.updateDisplayMenu(display: display, asSubMenu: asSubMenu, numOfDisplays: numOfDisplays)
      }
      if combine {
        self.addCombinedDisplayMenuBlock()
      }
    }
    self.addDefaultMenuOptions()
  }

  func addSliderItem(monitorSubMenu: NSMenu, sliderHandler: SliderHandler) {
    let item = NSMenuItem()
    item.view = sliderHandler.view
    monitorSubMenu.insertItem(item, at: 0)
    if app.macOS10() {
      let sliderHeaderItem = NSMenuItem()
      let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemGray, .font: NSFont.systemFont(ofSize: 12)]
      sliderHeaderItem.attributedTitle = NSAttributedString(string: sliderHandler.title, attributes: attrs)
      monitorSubMenu.insertItem(sliderHeaderItem, at: 0)
    }
  }

  func setupMenuSliderHandler(command: Command, display: Display, title: String) -> SliderHandler {
    if prefs.integer(forKey: PrefKey.multiSliders.rawValue) == MultiSliders.combine.rawValue, let combinedHandler = self.combinedSliderHandler[command] {
      combinedHandler.addDisplay(display)
      display.sliderHandler[command] = combinedHandler
      return combinedHandler
    } else {
      let sliderHandler = SliderHandler(display: display, command: command, title: title)
      if prefs.integer(forKey: PrefKey.multiSliders.rawValue) == MultiSliders.combine.rawValue {
        self.combinedSliderHandler[command] = sliderHandler
      }
      display.sliderHandler[command] = sliderHandler
      return sliderHandler
    }
  }

  func addDisplayMenuBlock(addedSliderHandlers: [SliderHandler], blockName: String, monitorSubMenu: NSMenu, numOfDisplays: Int, asSubMenu: Bool) {
    for handler in addedSliderHandlers {
      self.addSliderItem(monitorSubMenu: monitorSubMenu, sliderHandler: handler)
    }
    if !addedSliderHandlers.isEmpty {
      self.appendMenuHeader(friendlyName: blockName, monitorSubMenu: monitorSubMenu, asSubMenu: asSubMenu, numOfDisplays: numOfDisplays)
    }
  }

  func addCombinedDisplayMenuBlock() {
    if let sliderHandler = self.combinedSliderHandler[.audioSpeakerVolume] {
      self.addSliderItem(monitorSubMenu: self, sliderHandler: sliderHandler)
    }
    if let sliderHandler = self.combinedSliderHandler[.contrast] {
      self.addSliderItem(monitorSubMenu: self, sliderHandler: sliderHandler)
    }
    if let sliderHandler = self.combinedSliderHandler[.brightness] {
      self.addSliderItem(monitorSubMenu: self, sliderHandler: sliderHandler)
    }
  }

  func updateDisplayMenu(display: Display, asSubMenu: Bool, numOfDisplays: Int) {
    os_log("Addig menu items for display %{public}@", type: .info, "\(display.identifier)")
    let monitorSubMenu: NSMenu = asSubMenu ? NSMenu() : self
    var addedSliderHandlers: [SliderHandler] = []
    display.sliderHandler[.audioSpeakerVolume] = nil
    if let otherDisplay = display as? OtherDisplay, !otherDisplay.isSw(), !display.readPrefAsBool(key: .unavailableDDC, for: .audioSpeakerVolume), !prefs.bool(forKey: PrefKey.hideVolume.rawValue) {
      let title = NSLocalizedString("Volume", comment: "Shown in menu")
      addedSliderHandlers.append(self.setupMenuSliderHandler(command: .audioSpeakerVolume, display: display, title: title))
    }
    display.sliderHandler[.contrast] = nil
    if let otherDisplay = display as? OtherDisplay, !otherDisplay.isSw(), !display.readPrefAsBool(key: .unavailableDDC, for: .contrast), prefs.bool(forKey: PrefKey.showContrast.rawValue) {
      let title = NSLocalizedString("Contrast", comment: "Shown in menu")
      addedSliderHandlers.append(self.setupMenuSliderHandler(command: .contrast, display: display, title: title))
    }
    display.sliderHandler[.brightness] = nil
    if !display.readPrefAsBool(key: .unavailableDDC, for: .brightness), !prefs.bool(forKey: PrefKey.hideBrightness.rawValue) {
      let title = NSLocalizedString("Brightness", comment: "Shown in menu")
      addedSliderHandlers.append(self.setupMenuSliderHandler(command: .brightness, display: display, title: title))
    }
    if prefs.integer(forKey: PrefKey.multiSliders.rawValue) != MultiSliders.combine.rawValue {
      self.addDisplayMenuBlock(addedSliderHandlers: addedSliderHandlers, blockName: display.readPrefAsString(key: .friendlyName) != "" ? display.readPrefAsString(key: .friendlyName) : display.name, monitorSubMenu: monitorSubMenu, numOfDisplays: numOfDisplays, asSubMenu: asSubMenu)
    }
    if addedSliderHandlers.count > 0, prefs.integer(forKey: PrefKey.menuIcon.rawValue) == MenuIcon.sliderOnly.rawValue {
      app.updateStatusItemVisibility(true)
    }
  }

  private func appendMenuHeader(friendlyName: String, monitorSubMenu: NSMenu, asSubMenu: Bool, numOfDisplays: Int) {
    let monitorMenuItem = NSMenuItem()
    if asSubMenu {
      monitorMenuItem.title = "\(friendlyName)"
      monitorMenuItem.submenu = monitorSubMenu
      self.insertItem(monitorMenuItem, at: 0)
    } else {
      let row = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
      row.autoresizingMask = [.width]
      let label = NSTextField(labelWithString: friendlyName)
      label.font = .systemFont(ofSize: 12, weight: .semibold)
      label.textColor = .secondaryLabelColor
      label.lineBreakMode = .byTruncatingTail
      label.frame = NSRect(x: 24, y: 5, width: 272, height: 18)
      label.autoresizingMask = [.width]
      label.toolTip = friendlyName
      row.addSubview(label)
      monitorMenuItem.view = row
      monitorSubMenu.insertItem(monitorMenuItem, at: 0)
    }
  }

  func updateMenuRelevantDisplay() {
    if prefs.integer(forKey: PrefKey.multiSliders.rawValue) == MultiSliders.relevant.rawValue {
      if let display = DisplayManager.shared.getCurrentDisplay(), display.identifier != self.lastMenuRelevantDisplayId {
        os_log("Menu must be refreshed as relevant display changed since last time.")
        self.lastMenuRelevantDisplayId = display.identifier
        self.updateMenus(dontClose: true)
      }
    }
  }

  func addDefaultMenuOptions() {
    RemoteBridge.shared.attachMenu(self)
  }
}
