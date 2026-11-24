import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

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
    /// Requires Accessibility permission and "Switch to Desktop N" enabled in System Settings > Keyboard > Keyboard Shortcuts > Mission Control.
    public static func switchToDesktopSpace(_ spaceIndex: Int) throws {
        guard (1...9).contains(spaceIndex) else {
            throw WindowManagerError.invalidSpaceIndex(spaceIndex)
        }
        guard isAccessibilityGranted else {
            throw WindowManagerError.accessibilityNotGranted
        }

        let keyCodes: [Int: CGKeyCode] = [
            1: CGKeyCode(kVK_ANSI_1),
            2: CGKeyCode(kVK_ANSI_2),
            3: CGKeyCode(kVK_ANSI_3),
            4: CGKeyCode(kVK_ANSI_4),
            5: CGKeyCode(kVK_ANSI_5),
            6: CGKeyCode(kVK_ANSI_6),
            7: CGKeyCode(kVK_ANSI_7),
            8: CGKeyCode(kVK_ANSI_8),
            9: CGKeyCode(kVK_ANSI_9)
        ]

        guard let keyCode = keyCodes[spaceIndex] else {
            throw WindowManagerError.invalidSpaceIndex(spaceIndex)
        }

        postKeyCombo(keyCode: keyCode, flags: .maskControl)
    }

    /// Steps left (negative) or right (positive) across Desktop Spaces using Control + Left/Right Arrow,
    /// which is enabled by default on macOS Mission Control.
    public static func stepDesktopSpace(direction: Int) throws {
        guard isAccessibilityGranted else {
            throw WindowManagerError.accessibilityNotGranted
        }
        let keyCode = direction >= 0 ? CGKeyCode(kVK_RightArrow) : CGKeyCode(kVK_LeftArrow)
        postKeyCombo(keyCode: keyCode, flags: .maskControl)
    }

    /// Best-effort creation of a new Desktop Space via Mission Control UI scripting.
    public static func createNewDesktopSpace() async -> Bool {
        guard isAccessibilityGranted else { return false }

        let scriptSource = """
        do shell script "open -a 'Mission Control'"
        delay 0.6
        tell application "System Events"
            tell process "Dock"
                try
                    click (first button of group 1 of group 1 of group 1 whose description is "add desktop")
                    delay 0.4
                    key code 53
                    return true
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
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = flags
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = flags
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
