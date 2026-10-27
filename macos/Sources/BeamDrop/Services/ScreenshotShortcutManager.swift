import AppKit
import Carbon
import Foundation
import ScreenCaptureKit
import UserNotifications

public final class ScreenshotShortcutManager: ObservableObject {
    public static let shared = ScreenshotShortcutManager()
    
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefD: EventHotKeyRef?
    private var hotKeyRefS: EventHotKeyRef?
    private var localMonitor: Any?
    private var isCapturing = false
    
    private init() {}
    
    public func start() {
        registerCarbonHotKeys()
        registerLocalMonitor()
    }
    
    public func stop() {
        if let refD = hotKeyRefD {
            UnregisterEventHotKey(refD)
            hotKeyRefD = nil
        }
        if let refS = hotKeyRefS {
            UnregisterEventHotKey(refS)
            hotKeyRefS = nil
        }
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        if let l = localMonitor {
            NSEvent.removeMonitor(l)
            localMonitor = nil
        }
    }
    
    private func registerCarbonHotKeys() {
        guard eventHandlerRef == nil else { return }
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handler: EventHandlerUPP = { (_, theEvent, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                theEvent,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr && (hotKeyID.id == 1 || hotKeyID.id == 2) {
                DispatchQueue.main.async {
                    ScreenshotShortcutManager.shared.captureAndSendScreenshot()
                }
            }
            return noErr
        }
        
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &eventHandlerRef)
        
        // Shortcut 1: Cmd + Shift + D (kVK_ANSI_D = 0x02) - system-wide global hotkey
        let hotKeyID1 = EventHotKeyID(signature: OSType(0x42445331), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(cmdKey | shiftKey), hotKeyID1, GetApplicationEventTarget(), 0, &hotKeyRefD)
        
        // Shortcut 2: Cmd + Option + S (kVK_ANSI_S = 0x01) - secondary alternative
        let hotKeyID2 = EventHotKeyID(signature: OSType(0x42445332), id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(cmdKey | optionKey), hotKeyID2, GetApplicationEventTarget(), 0, &hotKeyRefS)
        
        print("ScreenshotShortcutManager: Registered system-wide Carbon HotKeys ⌘⇧D and ⌘⌥S")
    }
    
    private func registerLocalMonitor() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if (flags == [.command, .shift] && (chars == "d" || event.keyCode == 2)) ||
               (flags == [.command, .option] && (chars == "s" || event.keyCode == 1)) {
                self?.captureAndSendScreenshot()
                return nil
            }
            return event
        }
    }
    
    public func captureAndSendScreenshot() {
        guard !isCapturing else { return }
        isCapturing = true
        
        Task { [weak self] in
            defer { self?.isCapturing = false }
            
            // 1. Verify Screen Recording permission
            if !CGPreflightScreenCaptureAccess() {
                print("ScreenshotShortcutManager: Screen Recording permission not granted")
                await MainActor.run {
                    CGRequestScreenCaptureAccess()
                    self?.notifyPermissionRequired()
                    NSSound.beep()
                }
                return
            }
            
            // Play camera shutter / screenshot chime immediately
            await MainActor.run { NSSound(named: "Glass")?.play() }
            
            // Format timestamped filename
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let dateStr = dateFormatter.string(from: Date())
            let fileName = "Mac_Screenshot_\(dateStr).png"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: tempURL)
            
            var capturedImage: CGImage? = nil
            
            // 2. Capture via modern ScreenCaptureKit (macOS 12.3+, Sequoia & Sonoma official API)
            // ScreenCaptureKit captures full windows, desktop, and UI without black-screen redaction
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                if let display = content.displays.first {
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let config = SCStreamConfiguration()
                    config.width = display.width
                    config.height = display.height
                    config.showsCursor = false
                    capturedImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    try? "SCK SUCCESS: \(display.width)x\(display.height)".write(toFile: "/tmp/sck_err.log", atomically: true, encoding: .utf8)
                }
            } catch {
                try? "SCK ERROR: \(error.localizedDescription) details: \(error)".write(toFile: "/tmp/sck_err.log", atomically: true, encoding: .utf8)
                print("ScreenCaptureKit error: \(error)")
            }
            
            guard let validImage = capturedImage else {
                print("ScreenshotShortcutManager: ScreenCaptureKit capture returned nil")
                await MainActor.run { NSSound.beep() }
                return
            }
            
            let rep = NSBitmapImageRep(cgImage: validImage)
            guard let pngData = rep.representation(using: .png, properties: [:]) else {
                await MainActor.run { NSSound.beep() }
                return
            }
            
            do {
                try pngData.write(to: tempURL)
            } catch {
                print("Failed to save screenshot: \(error)")
                return
            }
            
            // Resolve destination target
            let discovery = DeviceDiscoveryService.shared
            var target = discovery.selectedDevice ?? discovery.discoveredDevices.first ?? PairedDevice(
                id: "moto-pad-60-pro-f5bfb763",
                name: "Moto Pad 60 Pro",
                host: "192.168.1.7",
                port: 8765,
                serverAuthToken: discovery.getSavedAuthToken(),
                clientAuthToken: UUID().uuidString,
                lastSeen: Date(),
                isOnline: true,
                isPaired: true
            )
            
            if target.serverAuthToken.isEmpty {
                target.serverAuthToken = discovery.getSavedAuthToken()
            }
            target.isPaired = true
            
            let item = TransferItem(url: tempURL)
            await MainActor.run {
                TransferClient.shared.startTransfer(item: item, target: target) { result in
                    switch result {
                    case .success:
                        NSSound(named: "Hero")?.play()
                    case .failure(let err):
                        print("Screenshot transfer failed: \(err)")
                    }
                }
                self?.notifyScreenshotDispatched(targetName: target.name, fileName: fileName)
            }
        }
    }
    
    private func notifyPermissionRequired() {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Screen Recording Required"
        content.body = "Please enable BeamDrop in System Settings > Screen Recording, then restart BeamDrop."
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        
        let script = """
        display notification "Please enable BeamDrop in System Settings > Screen & System Audio Recording." with title "Screen Recording Required"
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func notifyScreenshotDispatched(targetName: String, fileName: String) {
        let content = UNMutableNotificationContent()
        content.title = "📸 Screenshot Sent to \(targetName)"
        content.body = "Captured Mac screen and saved to Pictures/LaptopTransfer/\(fileName)"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        
        let script = """
        display notification "Sending \(fileName) to \(targetName) (Pictures/LaptopTransfer)" with title "BeamDrop Screenshot (⌘⇧D)"
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
    }
}
