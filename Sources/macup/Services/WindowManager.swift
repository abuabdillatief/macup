import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

// Private CoreGraphics Space query APIs (read-only; work without disabling SIP).
@_silgen_name("CGSMainConnectionID")
private func _CGSMainConnectionID() -> UInt32

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func _CGSCopyManagedDisplaySpaces(_ cid: UInt32) -> CFArray

public struct DesktopSpaceInfo: Sendable {
    /// 1-based index of the active regular Desktop Space (type == 0) on the primary display.
    public let activeIndex: Int
    /// Total number of regular Desktop Spaces (type == 0) on the primary display.
    public let totalCount: Int
}

public enum WindowManagerError: LocalizedError {
    case accessibilityNotGranted
    case noWindowFound(String)
    case couldNotSetFrame(String)
    case invalidSpaceIndex(Int)

    public var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility permission is required to move/resize windows and switch desktops."
        case .noWindowFound(let app):
            return "No movable window found for \(app)."
        case .couldNotSetFrame(let app):
            return "Could not resize or reposition window for \(app)."
        case .invalidSpaceIndex(let index):
            return "Desktop space index \(index) must be between 1 and 9."
        }
    }
}

public enum WindowManager {
    public static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public static func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Converts Cocoa NSScreen.visibleFrame (bottom-left origin) to Accessibility (top-left origin).
    public static func visibleTopLeftFrame(forScreenIndex index: Int) -> CGRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return CGRect(x: 0, y: 25, width: 1440, height: 875)
        }
        let primaryHeight = screens[0].frame.height
        let screen = (index >= 0 && index < screens.count) ? screens[index] : screens[0]
        let visible = screen.visibleFrame
        let topY = primaryHeight - (visible.origin.y + visible.height)
        return CGRect(x: visible.origin.x, y: topY, width: visible.width, height: visible.height)
    }

    /// Positions the frontmost/main window of the given process ID.
    public static func positionWindow(
        pid: pid_t,
        appName: String,
        placement: WindowPlacement,
        screenIndex: Int
    ) throws {
        guard placement != .none else { return }
        guard isAccessibilityGranted else {
            throw WindowManagerError.accessibilityNotGranted
        }

        let visibleFrame = visibleTopLeftFrame(forScreenIndex: screenIndex)
        guard let target = placement.targetFrame(in: visibleFrame) else { return }

        let appElement = AXUIElementCreateApplication(pid)
        guard let window = findTargetWindow(for: appElement) else {
            throw WindowManagerError.noWindowFound(appName)
        }

        // Un-minimize if minimized
        var minimizedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
           let isMinimized = minimizedValue as? Bool, isMinimized {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        var origin = target.origin
        var size = target.size

        guard let posVal = AXValueCreate(.cgPoint, &origin),
              let sizeVal = AXValueCreate(.cgSize, &size) else {
            throw WindowManagerError.couldNotSetFrame(appName)
        }

        // Set position, then size, then position again (handles apps that clamp size/pos while moving across displays)
        let posErr1 = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        let sizeErr = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        let posErr2 = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)

        if posErr1 != .success && sizeErr != .success && posErr2 != .success {
            throw WindowManagerError.couldNotSetFrame(appName)
        }

        // Raise window
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    private static func findTargetWindow(for appElement: AXUIElement) -> AXUIElement? {
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
           let focused = focusedRef {
            return (focused as! AXUIElement)
        }

        var mainRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainRef) == .success,
           let main = mainRef {
            return (main as! AXUIElement)
        }

        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for win in windows {
                var subroleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(win, kAXSubroleAttribute as CFString, &subroleRef) == .success,
                   let subrole = subroleRef as? String,
                   subrole == kAXStandardWindowSubrole as String {
                    return win
                }
            }
            return windows.first
        }

        return nil
    }

    /// Queries the exact active Desktop Space index (1-based) and total Desktop Space count
    /// on the primary display using CoreGraphics managed display spaces.
    public static func currentDesktopSpaceInfo() -> DesktopSpaceInfo? {
        let cid = _CGSMainConnectionID()
        guard let displays = _CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]],
              let primary = displays.first,
              let allSpaces = primary["Spaces"] as? [[String: Any]] else {
            return nil
        }

        // type == 0 are regular user Desktop Spaces (excluding full-screen app spaces)
        let desktopSpaces = allSpaces.filter { ($0["type"] as? Int ?? 0) == 0 }
        guard !desktopSpaces.isEmpty else { return nil }

        let currentID = (primary["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
        let activeIdx: Int
        if let cid = currentID,
           let found = desktopSpaces.firstIndex(where: { ($0["ManagedSpaceID"] as? Int) == cid }) {
            activeIdx = found + 1
        } else {
            activeIdx = 1
        }
        return DesktopSpaceInfo(activeIndex: activeIdx, totalCount: desktopSpaces.count)
    }

    /// Number of accessible windows of `pid` currently visible on the active Space.
    public static func visibleWindowCount(pid: pid_t) -> Int {
        guard isAccessibilityGranted else { return 0 }
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            return windows.count
        }
        return 0
    }

    /// Attempts to trigger an app's "New Window" menu item via Accessibility (works without switching Spaces).
    @discardableResult
    public static func triggerNewWindowMenu(pid: pid_t) -> Bool {
        guard isAccessibilityGranted else { return false }
        let appElement = AXUIElementCreateApplication(pid)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef else {
            return false
        }
        let barElement = menuBar as! AXUIElement
        guard let newWinItem = findAXElement(in: barElement, maxDepth: 4, matching: { el in
            let role = axString(el, kAXRoleAttribute) ?? ""
            guard role == kAXMenuItemRole as String else { return false }
            let title = (axString(el, kAXTitleAttribute) ?? "").lowercased()
            return title == "new window" || title == "new browser window"
        }) else {
            return false
        }
        return AXUIElementPerformAction(newWinItem, kAXPressAction as CFString) == .success
    }

    /// Ensures Desktop Space `targetIndex` (1...9) exists — automatically creating missing Spaces
    /// via Mission Control's Accessibility UI — and switches directly to it.
    /// Uses pure Accessibility (`AXUIElement` on `com.apple.dock`), requiring no System Events Automation
    /// permission and no manually enabled Mission Control keyboard shortcuts.
    public static func ensureAndSwitchToDesktopSpace(
        _ targetIndex: Int,
        log: @escaping @Sendable (String) -> Void
    ) async -> Bool {
        guard (1...9).contains(targetIndex) else { return false }
        guard isAccessibilityGranted else {
            log("Accessibility permission is not granted.")
            return false
        }

        if let info = currentDesktopSpaceInfo() {
            log("Spaces state: active=Desktop \(info.activeIndex), total=\(info.totalCount).")
            if info.activeIndex == targetIndex {
                return true
            }
        }

        // Open Mission Control
        guard openMissionControl() else {
            log("Failed to open Mission Control.")
            return false
        }
        try? await Task.sleep(nanoseconds: 550_000_000)

        // Move mouse near top-right so Mission Control expands the Spaces bar on macOS Sonoma/Ventura
        let primaryWidth = NSScreen.screens.first?.frame.width ?? 1440
        CGWarpMouseCursorPosition(CGPoint(x: primaryWidth - 40, y: 20))
        try? await Task.sleep(nanoseconds: 400_000_000)

        guard let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier else {
            closeMissionControl()
            log("Could not locate Dock process.")
            return false
        }
        let dockApp = AXUIElementCreateApplication(dockPID)

        // 1. Create any missing Desktop Spaces until totalCount >= targetIndex
        var safety = 0
        while let info = currentDesktopSpaceInfo(), info.totalCount < targetIndex, safety < 8 {
            safety += 1
            guard let addButton = findAddDesktopButton(in: dockApp) else {
                log("Could not find 'add desktop' button in Mission Control.")
                break
            }
            let beforeCount = info.totalCount
            let err = AXUIElementPerformAction(addButton, kAXPressAction as CFString)
            if err != .success {
                log("Failed to press 'add desktop' button (AXError \(err.rawValue)).")
                break
            }
            // Wait up to 1.2s for totalCount to increase
            var increased = false
            for _ in 0..<12 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if let updated = currentDesktopSpaceInfo(), updated.totalCount > beforeCount {
                    increased = true
                    log("Created Desktop \(updated.totalCount).")
                    break
                }
            }
            if !increased {
                log("Pressed 'add desktop' but space count stayed at \(beforeCount).")
                break
            }
        }

        // 2. Click the target Desktop Space button in Mission Control (switches AND closes Mission Control)
        if let spaceBtn = findDesktopSpaceButton(in: dockApp, targetIndex: targetIndex) {
            let err = AXUIElementPerformAction(spaceBtn, kAXPressAction as CFString)
            if err == .success {
                for _ in 0..<15 {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    if let updated = currentDesktopSpaceInfo(), updated.activeIndex == targetIndex {
                        // Give Mission Control exit animation a moment to finish
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        return true
                    }
                }
            } else {
                log("Failed to press Desktop \(targetIndex) button (AXError \(err.rawValue)).")
            }
        } else {
            log("Could not find Desktop \(targetIndex) button in Mission Control.")
        }

        // Close Mission Control if still open
        closeMissionControl()
        try? await Task.sleep(nanoseconds: 400_000_000)

        // Final check
        if let updated = currentDesktopSpaceInfo(), updated.activeIndex == targetIndex {
            return true
        }
        return false
    }

    private static func openMissionControl() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Mission Control"]
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func closeMissionControl() {
        postKeyCombo(keyCode: CGKeyCode(kVK_Escape), flags: [])
    }

    private static func findAddDesktopButton(in dockApp: AXUIElement) -> AXUIElement? {
        findAXElement(in: dockApp, maxDepth: 10) { el in
            let role = axString(el, kAXRoleAttribute) ?? ""
            guard role == kAXButtonRole as String else { return false }
            let ident = (axString(el, kAXIdentifierAttribute) ?? "").lowercased()
            let desc = (axString(el, kAXDescriptionAttribute) ?? "").lowercased()
            let title = (axString(el, kAXTitleAttribute) ?? "").lowercased()
            return ident == "mc.spaces.add"
                || desc.contains("add desktop")
                || title.contains("add desktop")
        }
    }

    private static func findDesktopSpaceButton(in dockApp: AXUIElement, targetIndex: Int) -> AXUIElement? {
        // First pass: look for explicit "Desktop N" title or description
        let exactLabel = "desktop \(targetIndex)"
        if let direct = findAXElement(in: dockApp, maxDepth: 10, matching: { el in
            let role = axString(el, kAXRoleAttribute) ?? ""
            guard role == kAXButtonRole as String else { return false }
            let desc = (axString(el, kAXDescriptionAttribute) ?? "").lowercased()
            let title = (axString(el, kAXTitleAttribute) ?? "").lowercased()
            return desc == exactLabel || title == exactLabel
                || desc.hasPrefix("\(exactLabel) ") || title.hasPrefix("\(exactLabel) ")
        }) {
            return direct
        }

        // Second pass: find mc.spaces.list (or AXList inside mc) and index its space buttons
        if let spacesList = findAXElement(in: dockApp, maxDepth: 10, matching: { el in
            let ident = (axString(el, kAXIdentifierAttribute) ?? "").lowercased()
            let role = axString(el, kAXRoleAttribute) ?? ""
            return ident == "mc.spaces.list" || role == kAXListRole as String
        }) {
            var buttons: [AXUIElement] = []
            collectAXElements(in: spacesList, maxDepth: 4, into: &buttons) { el in
                let role = axString(el, kAXRoleAttribute) ?? ""
                guard role == kAXButtonRole as String else { return false }
                let ident = (axString(el, kAXIdentifierAttribute) ?? "").lowercased()
                let desc = (axString(el, kAXDescriptionAttribute) ?? "").lowercased()
                // Exclude add/close buttons
                return ident != "mc.spaces.add" && !desc.contains("add desktop") && !desc.contains("close")
            }
            if targetIndex >= 1 && targetIndex <= buttons.count {
                return buttons[targetIndex - 1]
            }
        }

        return nil
    }

    private static func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return nil
        }
        return ref as? String
    }

    private static func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success,
              let children = ref as? [AXUIElement] else {
            return []
        }
        return children
    }

    private static func findAXElement(
        in root: AXUIElement,
        maxDepth: Int,
        matching predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        if predicate(root) { return root }
        guard maxDepth > 0 else { return nil }
        for child in axChildren(root) {
            if let found = findAXElement(in: child, maxDepth: maxDepth - 1, matching: predicate) {
                return found
            }
        }
        return nil
    }

    private static func collectAXElements(
        in root: AXUIElement,
        maxDepth: Int,
        into results: inout [AXUIElement],
        matching predicate: (AXUIElement) -> Bool
    ) {
        if predicate(root) { results.append(root) }
        guard maxDepth > 0 else { return }
        for child in axChildren(root) {
            collectAXElements(in: child, maxDepth: maxDepth - 1, into: &results, matching: predicate)
        }
    }

    /// Checks whether macOS Mission Control's "Switch to Desktop N" shortcut (Control + 1...9)
    /// is enabled in `com.apple.symbolichotkeys` (keys 118...126).
    public static func isDirectDesktopShortcutEnabled(for spaceIndex: Int) -> Bool {
        guard (1...9).contains(spaceIndex) else { return false }
        let key = String(117 + spaceIndex)
        guard let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys"),
              let entry = hotkeys[key] as? [String: Any],
              let enabled = entry["enabled"] as? Bool else {
            return false
        }
        return enabled
    }

    /// Switches to macOS Desktop Space 1...9 using the standard Mission Control shortcut (Control + 1...9).
    /// Uses System Events (which reliably triggers Mission Control symbolic hotkeys on macOS 14+),
    /// with CGEvent fallback.
    public static func switchToDesktopSpace(_ spaceIndex: Int) throws {
        guard (1...9).contains(spaceIndex) else {
            throw WindowManagerError.invalidSpaceIndex(spaceIndex)
        }
        guard isAccessibilityGranted else {
            throw WindowManagerError.accessibilityNotGranted
        }

        let keyCodes: [Int: Int] = [
            1: kVK_ANSI_1,
            2: kVK_ANSI_2,
            3: kVK_ANSI_3,
            4: kVK_ANSI_4,
            5: kVK_ANSI_5,
            6: kVK_ANSI_6,
            7: kVK_ANSI_7,
            8: kVK_ANSI_8,
            9: kVK_ANSI_9
        ]

        guard let keyCode = keyCodes[spaceIndex] else {
            throw WindowManagerError.invalidSpaceIndex(spaceIndex)
        }

        if !sendSystemEventsControlKey(keyCode: keyCode) {
            postKeyCombo(keyCode: CGKeyCode(keyCode), flags: .maskControl)
        }
    }

    /// Steps left (negative) or right (positive) across Desktop Spaces using Control + Left/Right Arrow,
    /// which is enabled by default on macOS Mission Control.
    public static func stepDesktopSpace(direction: Int) throws {
        guard isAccessibilityGranted else {
            throw WindowManagerError.accessibilityNotGranted
        }
        let keyCode = direction >= 0 ? kVK_RightArrow : kVK_LeftArrow
        if !sendSystemEventsControlKey(keyCode: keyCode) {
            postKeyCombo(keyCode: CGKeyCode(keyCode), flags: [.maskControl, .maskSecondaryFn])
        }
    }

    private static func sendSystemEventsControlKey(keyCode: Int) -> Bool {
        let scriptSource = """
        tell application "System Events"
            key code \(keyCode) using control down
        end tell
        """
        var errorDict: NSDictionary?
        let script = NSAppleScript(source: scriptSource)
        _ = script?.executeAndReturnError(&errorDict)
        return errorDict == nil
    }

    /// Best-effort creation of a new Desktop Space via Mission Control UI scripting.
    public static func createNewDesktopSpace() async -> Bool {
        guard isAccessibilityGranted else { return false }

        let scriptSource = """
        do shell script "open -a 'Mission Control'"
        delay 0.8
        tell application "System Events"
            tell process "Dock"
                try
                    set addBtn to missing value
                    repeat with uiElem in entire contents of group 1
                        try
                            if (role of uiElem is "AXButton") and (description of uiElem is "add desktop") then
                                set addBtn to uiElem
                                exit repeat
                            end if
                        end try
                    end repeat
                    if addBtn is not missing value then
                        click addBtn
                        delay 0.5
                        key code 53
                        return true
                    else
                        key code 53
                        return false
                    end if
                on error
                    try
                        key code 53
                    end try
                    return false
                end try
            end tell
        end tell
        """

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var errorDict: NSDictionary?
                let script = NSAppleScript(source: scriptSource)
                let result = script?.executeAndReturnError(&errorDict)
                continuation.resume(returning: result?.booleanValue ?? false)
            }
        }
    }

    private static func postKeyCombo(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        // Explicitly send Control modifier down/up around the key event so Dock/Mission Control reliably captures it
        if flags.contains(.maskControl),
           let ctrlDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Control), keyDown: true) {
            ctrlDown.flags = flags
            ctrlDown.post(tap: .cghidEventTap)
        }
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = flags
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = flags
            keyUp.post(tap: .cghidEventTap)
        }
        if flags.contains(.maskControl),
           let ctrlUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Control), keyDown: false) {
            ctrlUp.flags = []
            ctrlUp.post(tap: .cghidEventTap)
        }
    }
}
