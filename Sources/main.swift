import AppKit
import CoreGraphics

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
    private let wallpaperBackupKey = "darkBaseWallpaperBackup"
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
        if prefs.dictionary(forKey: wallpaperBackupKey) == nil {
            menu.addItem(menuItem("Use Dark Base Wallpaper…", #selector(useDarkWallpaper)))
        } else {
            menu.addItem(menuItem("Restore Previous Wallpaper…", #selector(restoreWallpaper)))
        }
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

    private func displayID(_ screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value) else { return nil }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }

    private func wallpaperAlert(_ title: String, _ message: String, action: String? = nil) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: action ?? "OK")
        if action != nil { alert.addButton(withTitle: "Cancel") }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func useDarkWallpaper() {
        let workspace = NSWorkspace.shared
        guard prefs.dictionary(forKey: wallpaperBackupKey) == nil else { return }
        guard let screen = NSScreen.screens.first, let display = displayID(screen),
              let original = workspace.desktopImageURL(for: screen), original.isFileURL,
              FileManager.default.isReadableFile(atPath: original.path) else {
            _ = wallpaperAlert("Wallpaper couldn’t be saved", "macOS didn’t provide a readable wallpaper for the main display. Choose a still image in System Settings → Wallpaper, then try again.")
            return
        }
        guard wallpaperAlert("Use a dark base wallpaper?", "Sets the main display’s system wallpaper to black for the current desktop. WallpaperMachine can still show its live wallpaper if it draws over the system wallpaper. macOS decides the icon colors. To undo this, use Restore Previous Wallpaper on this desktop.", action: "Use Dark Base") else { return }
        guard NSScreen.screens.first.flatMap(displayID) == display,
              workspace.desktopImageURL(for: screen) == original else {
            _ = wallpaperAlert("Wallpaper changed", "Return to the desktop you want to update and try again.")
            return
        }
        do {
            let options = workspace.desktopImageOptions(for: screen) ?? [:]
            let savedOptions = try NSKeyedArchiver.archivedData(withRootObject: options.reduce(into: [String: Any]()) { $0[$1.key.rawValue] = $1.value }, requiringSecureCoding: true)
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("NotchShade", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let dark = support.appendingPathComponent("Dark Base.png")
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
                throw CocoaError(.fileWriteUnknown)
            }
            for y in 0..<32 {
                for x in 0..<32 { bitmap.setColor(.black, atX: x, y: y) }
            }
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: dark, options: .atomic)
            prefs.set(["display": display, "original": original.path, "options": savedOptions], forKey: wallpaperBackupKey)
            try workspace.setDesktopImageURL(dark, for: screen, options: [.imageScaling: NSImageScaling.scaleAxesIndependently.rawValue])
        } catch {
            _ = wallpaperAlert("Couldn’t set the dark base", error.localizedDescription)
        }
        updateMenu()
    }

    @objc private func restoreWallpaper() {
        guard let backup = prefs.dictionary(forKey: wallpaperBackupKey),
              let display = backup["display"] as? String,
              let path = backup["original"] as? String,
              let data = backup["options"] as? Data else { return }
        guard let screen = NSScreen.screens.first(where: { displayID($0) == display }) else {
            _ = wallpaperAlert("Display unavailable", "Reconnect the display where you set the dark base, then try again.")
            return
        }
        guard wallpaperAlert("Restore previous wallpaper?", "The saved wallpaper will be applied to the current desktop on the original display.", action: "Restore") else { return }
        do {
            let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, NSString.self, NSNumber.self, NSColor.self], from: data) as? [String: Any] ?? [:]
            let options = Dictionary(uniqueKeysWithValues: decoded.map { (NSWorkspace.DesktopImageOptionKey(rawValue: $0.key), $0.value) })
            try NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: options)
            prefs.removeObject(forKey: wallpaperBackupKey)
        } catch {
            _ = wallpaperAlert("Couldn’t restore wallpaper", error.localizedDescription)
        }
        updateMenu()
    }

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
