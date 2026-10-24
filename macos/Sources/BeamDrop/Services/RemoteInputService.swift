import Foundation
import AppKit
import CoreGraphics

public final class RemoteInputService {
    public static let shared = RemoteInputService()
    
    private init() {}
    
    // Virtual key codes for macOS
    private let keyMap: [String: CGKeyCode] = [
        "Left": 123,
        "Right": 124,
        "Down": 125,
        "Up": 126,
        "Return": 36,
        "Enter": 36,
        "Backspace": 51,
        "Space": 49,
        "Escape": 53,
        "Esc": 53,
        "Tab": 48,
        "F5": 96,
        "b": 11,
        "B": 11,
        "w": 13,
        "W": 13
    ]
    
    public func handleInput(_ input: KdeRemoteInput) {
        switch input.type {
        case "move":
            if let dx = input.dx, let dy = input.dy {
                moveMouse(dx: CGFloat(dx), dy: CGFloat(dy))
            }
        case "click":
            clickMouse(button: input.button ?? "left")
        case "scroll":
            if let dy = input.dy {
                scrollWheel(dy: CGFloat(dy))
            }
        case "key":
            if let key = input.key {
                pressKey(key: key)
            }
        case "text":
            if let text = input.text {
                typeText(text)
            }
        default:
            break
        }
    }
    
    public func moveMouse(dx: CGFloat, dy: CGFloat) {
        guard let currentEvent = CGEvent(source: nil) else { return }
        let currentPos = currentEvent.location
        let newX = currentPos.x + dx
        let newY = currentPos.y + dy
        let newPos = CGPoint(x: newX, y: newY)
        
        if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: newPos, mouseButton: .left) {
            moveEvent.post(tap: .cghidEventTap)
        }
    }
    
    public func clickMouse(button: String) {
        guard let currentEvent = CGEvent(source: nil) else { return }
        let pos = currentEvent.location
        
        switch button {
        case "right":
            let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: pos, mouseButton: .right)
            let up = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: pos, mouseButton: .right)
            down?.post(tap: .cghidEventTap)
            usleep(10_000)
            up?.post(tap: .cghidEventTap)
            
        case "double":
            let down1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pos, mouseButton: .left)
            let up1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: pos, mouseButton: .left)
            let down2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pos, mouseButton: .left)
            let up2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: pos, mouseButton: .left)
            down2?.setIntegerValueField(.mouseEventClickState, value: 2)
            up2?.setIntegerValueField(.mouseEventClickState, value: 2)
            
            down1?.post(tap: .cghidEventTap)
            up1?.post(tap: .cghidEventTap)
            usleep(15_000)
            down2?.post(tap: .cghidEventTap)
            up2?.post(tap: .cghidEventTap)
            
        default: // "left"
            let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pos, mouseButton: .left)
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: pos, mouseButton: .left)
            down?.post(tap: .cghidEventTap)
            usleep(10_000)
            up?.post(tap: .cghidEventTap)
        }
    }
    
    public func scrollWheel(dy: CGFloat) {
        let deltaY = Int32(dy * 2.5)
        let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: deltaY,
            wheel2: 0,
            wheel3: 0
        )
        scrollEvent?.post(tap: .cghidEventTap)
    }
    
    public func pressKey(key: String) {
        if let keyCode = keyMap[key] {
            let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
            down?.post(tap: .cghidEventTap)
            usleep(15_000)
            up?.post(tap: .cghidEventTap)
        } else {
            // Fallback for single characters or names via AppleScript
            let escaped = key.replacingOccurrences(of: "\"", with: "\\\"")
            let script = "tell application \"System Events\" to keystroke \"\(escaped)\""
            executeAppleScript(script)
        }
    }
    
    public func typeText(_ text: String) {
        let utf16Chars = Array(text.utf16)
        if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
            event.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
            event.post(tap: .cghidEventTap)
            
            let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            upEvent?.post(tap: .cghidEventTap)
        } else {
            let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                              .replacingOccurrences(of: "\"", with: "\\\"")
            let script = "tell application \"System Events\" to keystroke \"\(escaped)\""
            executeAppleScript(script)
        }
    }
    
    private func executeAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let script = NSAppleScript(source: source) {
                script.executeAndReturnError(&error)
            }
        }
    }
}
