<p align="center"><img src="Resources/AppIcon.png" width="160" alt="NotchShade icon"></p>

# NotchShade

A lightweight native macOS menu bar app that blends the camera notch into a black strip across the top of your screen. The camera remains usable.

## Download and install

[Download NotchShade 1.5.1 for Apple Silicon](https://github.com/glorrified/NotchShade/releases/download/v1.5.1/NotchShade-1.5.1.zip).

Unzip, move NotchShade.app to Applications, and open it. Use its rectangle icon in the menu bar to enable the strip or adjust its height. Quit and replace any older copy before installing an update.

Requires an Apple Silicon Mac running macOS 13 or newer. The app is locally signed, not Apple-notarized. If macOS blocks it, review the source, then use System Settings → Privacy & Security → Open Anyway for this app.

## Features

- Automatic notch detection and display-change handling.
- Automatic strip height includes one extra point for coverage.
- Optional additional height and support for displays without a notch.
- Click-through overlay with support for Spaces and fullscreen auxiliary windows.
- Open at Login toggle, persistent preferences, and a custom app icon.
- No network code, camera access, Accessibility permission, or screen recording permission.

To launch automatically when you sign in, move NotchShade to Applications and enable **Open at Login** in its menu. A checkmark means it is enabled; click again to disable it. If the menu says **Allow in Settings…**, click it and allow NotchShade in System Settings → General → Login Items & Extensions. The menu checks the current macOS setting whenever you open it.

## Live wallpapers and icon contrast

NotchShade draws an independent overlay rather than changing your wallpaper. Ordinary live wallpaper windows should remain underneath it. Compatibility with WallpaperMachine is not guaranteed for every window mode.

macOS controls menu bar icon contrast. If menu text is hard to read, try Dark appearance in System Settings. You can change your wallpaper separately in System Settings → Wallpaper.

## Build from source

Install Apple's Command Line Tools, then run:

```sh
bash build.sh
```

The build produces `build/NotchShade.zip` with a locally signed Apple Silicon app. No Xcode project or external dependencies are needed. The Swift source is in `Sources/main.swift`, with the app metadata and icon in `Resources/`.

## Validation

The build verifies the app signature. Check strip coverage with your live wallpaper running and confirm Open at Login shows the current system setting.
