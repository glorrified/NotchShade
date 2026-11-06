import AppKit
import CoreGraphics
import ServiceManagement

final class ShadePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // AppKit normally pushes windows below the menu bar. This panel deliberately
    // occupies that area; applying the default constraint creates a second band.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private var panels: [NSNumber: [ShadePanel]] = [:]
    private let prefs = UserDefaults.standard
    private var enabled: Bool { !prefs.bool(forKey: "disabled") }
    private var allDisplays: Bool { prefs.bool(forKey: "allDisplays") || CommandLine.arguments.contains("--smoke-test") }
    private var extraHeight: Int { prefs.integer(forKey: "extraHeight") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if !prefs.bool(forKey: "fixedPositionV11") {
            prefs.set(0, forKey: "extraHeight")
            prefs.set(true, forKey: "fixedPositionV11")
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "NotchShade")
        item.button?.toolTip = "NotchShade — black out the notch area"
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // The panels follow Spaces themselves. Recreating them during a
        // full-screen transition briefly exposes the wallpaper underneath.
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
        refresh()
        if CommandLine.arguments.contains("--smoke-test") {
            print("NotchShade started: \(NSScreen.screens.count) display(s), \(panels.values.reduce(0) { $0 + $1.count }) shade windows.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
        }
    }

    private func menuItem(_ title: String, _ action: Selector, checked: Bool? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        if let checked { entry.state = checked ? .on : .off }
        return entry
    }

    private func updateMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let title = NSMenuItem(title: "NotchShade", action: nil, keyEquivalent: "")
        menu.addItem(title)
        menu.addItem(menuItem("Black strip enabled", #selector(toggle), checked: enabled))
        menu.addItem(menuItem("Show black strip on all displays", #selector(toggleDisplays), checked: allDisplays))
        let height = NSMenuItem(title: "Strip height", action: nil, keyEquivalent: "")
        let heights = NSMenu()
        for value in [0, 2, 4, 8, 16] {
            let choice = menuItem(value == 0 ? "Automatic" : "Automatic + \(value) points", #selector(setHeight(_:)), checked: extraHeight == value)
            choice.tag = value
            heights.addItem(choice)
        }
        height.submenu = heights
        menu.addItem(height)
        menu.addItem(.separator())
        let loginItem = menuItem("Open at Login", #selector(toggleOpenAtLogin))
        loginItem.tag = 100
        updateLoginItem(loginItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        let count = NSScreen.screens.filter { $0.safeAreaInsets.top > 0 }.count
        menu.addItem(NSMenuItem(title: "\(count) notched display(s) detected", action: nil, keyEquivalent: ""))
        menu.addItem(menuItem("Help & startup instructions…", #selector(help)))
        menu.addItem(.separator())
        let quit = menuItem("Quit NotchShade", #selector(quitApp))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
        item.menu = menu
    }

    private func updateLoginItem(_ item: NSMenuItem) {
        let status = SMAppService.mainApp.status
        item.title = status == .requiresApproval ? "Open at Login — Allow in Settings…" : "Open at Login"
        item.state = status == .enabled ? .on : .off
    }

    func menuWillOpen(_ menu: NSMenu) {
        if let loginItem = menu.item(withTag: 100) { updateLoginItem(loginItem) }
    }

    @objc private func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t change Open at Login"
            alert.informativeText = "Keep NotchShade in Applications and try again. You can also manage it in System Settings → General → Login Items & Extensions.\n\n" + error.localizedDescription
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        updateMenu()
    }

    @objc private func refresh() {
        var activePanels: [NSNumber: [ShadePanel]] = [:]
        if enabled {
            for screen in NSScreen.screens where allDisplays || screen.safeAreaInsets.top > 0 {
                guard let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
                let height = min(screen.frame.height, max(screen.safeAreaInsets.top, NSStatusBar.system.thickness) + 1 + CGFloat(extraHeight))
                let rect = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
                let shades = panels[display] ?? makeShades(frame: rect)
                for panel in shades {
                    if panel.frame != rect { panel.setFrame(rect, display: true, animate: false) }
                    if !panel.isVisible { panel.orderFrontRegardless() }
                    if CommandLine.arguments.contains("--smoke-test") {
                        print("Level \(panel.level.rawValue): requested \(rect), actual \(panel.frame)")
                        precondition(panel.frame == rect, "Shade must stay inside its requested top-edge bounds")
                    }
                }
                activePanels[display] = shades
            }
        }
        for (display, shades) in panels where activePanels[display] == nil {
            for panel in shades { panel.close() }
        }
        panels = activePanels
        updateMenu()
    }

    private func makeShades(frame: NSRect) -> [ShadePanel] {
        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow)) + 1
        let overlayLevel = NSWindow.Level.mainMenu.rawValue - 1
        // The desktop shade sits directly above live wallpaper windows. It
        // can cover the desktop while macOS recomposes the higher overlay.
        let desktop = makeShade(frame: frame, level: desktopLevel)
        desktop.collectionBehavior.insert(.fullScreenNone)
        let overlay = makeShade(frame: frame, level: overlayLevel)
        overlay.collectionBehavior.formUnion([.fullScreenAuxiliary, .canJoinAllApplications])
        return [desktop, overlay]
    }

    private func makeShade(frame: NSRect, level: Int) -> ShadePanel {
        let panel = ShadePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.setFrame(frame, display: false)
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.level = NSWindow.Level(rawValue: level)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        return panel
    }

    @objc private func toggle() { prefs.set(enabled, forKey: "disabled"); refresh() }
    @objc private func toggleDisplays() { prefs.set(!allDisplays, forKey: "allDisplays"); refresh() }
    @objc private func setHeight(_ sender: NSMenuItem) { prefs.set(sender.tag, forKey: "extraHeight"); refresh() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    @objc private func help() {
        let alert = NSAlert()
        alert.messageText = "NotchShade"
        alert.informativeText = "A black strip blends the camera notch into the top of your screen. Your camera continues to work.\n\nWallpaper apps can keep running: the strip sits above ordinary wallpaper windows. System menu text remains above the strip; macOS controls its appearance and transparency.\n\nTo start automatically when you sign in: move NotchShade to Applications, open it, then enable ‘Open at Login’ in this menu. Click it again to turn it off. If macOS requests approval, allow it in System Settings → General → Login Items & Extensions.\n\nIf menu text is hard to read, try Dark appearance in System Settings. If no notch is detected, enable ‘Show black strip on all displays’. Quitting immediately removes the strip."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
