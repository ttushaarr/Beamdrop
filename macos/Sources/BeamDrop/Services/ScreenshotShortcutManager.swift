import AppKit
import Foundation
import UserNotifications

public final class ScreenshotShortcutManager: ObservableObject {
    public static let shared = ScreenshotShortcutManager()
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isCapturing = false
    
    private init() {}
    
    public func start() {
        guard globalMonitor == nil && localMonitor == nil else { return }
        
        // Global monitor (captures shortcut when other apps are focused)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        
        // Local monitor (captures shortcut when BeamDrop is focused)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.isShortcutMatch(event) == true {
                self?.captureAndSendScreenshot()
                return nil // Consume event
            }
            return event
        }
        
        print("ScreenshotShortcutManager: Registered global shortcut ⌘⇧D / ⌘⌥S")
    }
    
    public func stop() {
        if let g = globalMonitor {
            NSEvent.removeMonitor(g)
            globalMonitor = nil
        }
        if let l = localMonitor {
            NSEvent.removeMonitor(l)
            localMonitor = nil
        }
    }
    
    private func isShortcutMatch(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        
        // Shortcut 1: Cmd + Shift + D
        if flags == [.command, .shift] && (chars == "d" || event.keyCode == 2) {
            return true
        }
        
        // Shortcut 2: Cmd + Option + S (keyCode 1 is 'S' on standard QWERTY)
        if flags == [.command, .option] && (event.keyCode == 1 || chars == "s" || chars == "ß") {
            return true
        }
        
        return false
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        if isShortcutMatch(event) {
            captureAndSendScreenshot()
        }
    }
    
    public func captureAndSendScreenshot() {
        guard !isCapturing else { return }
        isCapturing = true
        
        DispatchQueue.main.async { [weak self] in
            defer { self?.isCapturing = false }
            
            guard let screen = NSScreen.main else {
                NSSound.beep()
                return
            }
            
            // Capture full display
            guard let cgImage = CGWindowListCreateImage(screen.frame, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]) else {
                NSSound.beep()
                return
            }
            
            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let pngData = rep.representation(using: .png, properties: [:]) else {
                NSSound.beep()
                return
            }
            
            // Play camera shutter / screenshot chime
            NSSound(named: "Glass")?.play()
            
            // Write to temporary file with clean timestamp
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let dateStr = dateFormatter.string(from: Date())
            let fileName = "Mac_Screenshot_\(dateStr).png"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            
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
            TransferClient.shared.startTransfer(item: item, target: target) { result in
                switch result {
                case .success:
                    NSSound(named: "Hero")?.play()
                case .failure(let err):
                    print("Screenshot transfer failed: \(err)")
                }
            }
            
            // Show macOS notification
            self?.notifyScreenshotDispatched(targetName: target.name, fileName: fileName)
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
