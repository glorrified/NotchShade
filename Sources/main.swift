import AppKit

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
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var panels: [NSPanel] = []
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
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
        refresh()
        if CommandLine.arguments.contains("--smoke-test") {
            print("NotchShade started: \(NSScreen.screens.count) display(s), \(panels.count) overlay(s).")
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
        let title = NSMenuItem(title: "NotchShade", action: nil, keyEquivalent: "")
        menu.addItem(title)
        menu.addItem(menuItem("Black strip enabled", #selector(toggle), checked: enabled))
        menu.addItem(menuItem("Include displays without a notch", #selector(toggleDisplays), checked: allDisplays))
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
        let count = NSScreen.screens.filter { $0.safeAreaInsets.top > 0 }.count
        menu.addItem(NSMenuItem(title: "\(count) notched display(s) detected", action: nil, keyEquivalent: ""))
        menu.addItem(menuItem("Help & startup instructions…", #selector(help)))
        menu.addItem(.separator())
        let quit = menuItem("Quit NotchShade", #selector(quitApp))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
        item.menu = menu
    }

    @objc private func refresh() {
        panels.forEach { $0.orderOut(nil); $0.close() }
        panels.removeAll()
        if enabled {
            for screen in NSScreen.screens where allDisplays || screen.safeAreaInsets.top > 0 {
                let height = min(screen.frame.height, max(screen.safeAreaInsets.top, NSStatusBar.system.thickness) + 1 + CGFloat(extraHeight))
                let rect = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
                let panel = ShadePanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.setFrame(rect, display: false)
                panel.backgroundColor = .black
                panel.isOpaque = true
                panel.hasShadow = false
                panel.ignoresMouseEvents = true
                panel.hidesOnDeactivate = false
                panel.isReleasedWhenClosed = false
                panel.isMovable = false
                panel.animationBehavior = .none
                // Above wallpaper/application content, below system menu text and menus.
                panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
                if #available(macOS 13.0, *) { panel.collectionBehavior.insert(.canJoinAllApplications) }
                panel.orderFrontRegardless()
                if CommandLine.arguments.contains("--smoke-test") {
                    print("Requested: \(rect); actual: \(panel.frame); safe inset: \(screen.safeAreaInsets.top)")
                    precondition(panel.frame == rect, "Overlay must stay inside its requested top-edge bounds")
                }
                panels.append(panel)
            }
        }
        updateMenu()
    }

    @objc private func toggle() { prefs.set(enabled, forKey: "disabled"); refresh() }
    @objc private func toggleDisplays() { prefs.set(!allDisplays, forKey: "allDisplays"); refresh() }
    @objc private func setHeight(_ sender: NSMenuItem) { prefs.set(sender.tag, forKey: "extraHeight"); refresh() }
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc private func help() {
        let alert = NSAlert()
        alert.messageText = "NotchShade"
        alert.informativeText = "A black strip blends the camera notch into the top of your screen. Your camera continues to work.\n\nWallpaper apps can keep running: the strip sits above ordinary wallpaper windows. System menu text remains above the strip; macOS controls its appearance and transparency.\n\nTo start automatically: move NotchShade to Applications, then add it in System Settings → General → Login Items & Extensions → Open at Login.\n\nIf menu text is hard to read, try Dark appearance in System Settings. If no notch is detected, enable ‘Include displays without a notch’. Quitting immediately removes the strip."
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
