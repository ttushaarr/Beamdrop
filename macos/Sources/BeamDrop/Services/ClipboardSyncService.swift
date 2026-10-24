import Foundation
import AppKit
import Combine
import UserNotifications

public class ClipboardSyncService: ObservableObject {
    public static let shared = ClipboardSyncService()
    
    @Published public var isSyncEnabled: Bool = true
    @Published public var lastSyncedText: String?
    @Published public var isSseConnected: Bool = false
    @Published public var syncDirection: String = "Idle"
    
    private var monitorTask: Task<Void, Never>?
    private var sseTask: Task<Void, Never>?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var lastSentToTablet: String?
    private var lastReceivedFromTablet: String?
    
    public init() {
        startMonitoringMacPasteboard()
        startSseConnection()
    }
    
    deinit {
        monitorTask?.cancel()
        sseTask?.cancel()
    }
    
    public func startMonitoringMacPasteboard() {
        monitorTask?.cancel()
        lastChangeCount = NSPasteboard.general.changeCount
        
        monitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 350_000_000) // check every 350ms
                guard let self = self else { break }
                self.checkMacPasteboard()
            }
        }
    }
    
    @MainActor
    private func checkMacPasteboard() {
        guard isSyncEnabled else { return }
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount
        
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        
        // Ignore if this text was just received from the tablet (prevent echo loops)
        if text == lastReceivedFromTablet || text == lastSentToTablet {
            return
        }
        
        lastSentToTablet = text
        sendClipboardToTablet(text: text)
    }
    
    public func sendClipboardToTablet(text: String) {
        let dev = DeviceDiscoveryService.shared.selectedDevice ?? DeviceDiscoveryService.shared.discoveredDevices.first(where: { $0.isPaired })
        let host = (dev?.host.isEmpty == false) ? dev!.host : "192.168.1.7"
        let port = (dev?.port ?? 0) > 0 ? dev!.port : 8765
        let token = (dev?.serverAuthToken.isEmpty == false) ? dev!.serverAuthToken : "e71cae5964a44470a759c097719e8cbeb124845567d0462ba93aaf096581e13f"
        
        guard let url = URL(string: "http://\(host):\(port)/api/v1/clipboard") else { return }
        
        Task {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 5.0
            
            let payload: [String: Any] = [
                "text": text,
                "timestamp": Int(Date().timeIntervalSince1970),
                "source": "mac"
            ]
            
            guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
            request.httpBody = body
            
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    await MainActor.run {
                        self.lastSyncedText = text
                        self.syncDirection = "Mac → Moto Pad"
                    }
                    print("[CLIPBOARD] Successfully pushed clipboard text to Moto Pad (\(text.count) chars)")
                }
            } catch {
                print("Failed to send clipboard to tablet: \(error)")
            }
        }
    }
    
    public func startSseConnection() {
        sseTask?.cancel()
        guard isSyncEnabled else { return }
        
        sseTask = Task { [weak self] in
            while !Task.isCancelled {
                let dev = DeviceDiscoveryService.shared.selectedDevice ?? DeviceDiscoveryService.shared.discoveredDevices.first(where: { $0.isPaired })
                let host = (dev?.host.isEmpty == false) ? dev!.host : "192.168.1.7"
                let port = (dev?.port ?? 0) > 0 ? dev!.port : 8765
                let token = (dev?.serverAuthToken.isEmpty == false) ? dev!.serverAuthToken : "e71cae5964a44470a759c097719e8cbeb124845567d0462ba93aaf096581e13f"
                
                guard let url = URL(string: "http://\(host):\(port)/api/v1/clipboard/events") else {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    continue
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 3600
                
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        continue
                    }
                    
                    await MainActor.run {
                        self?.isSseConnected = true
                    }
                    
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonStr = String(line.dropFirst(6))
                            if let data = jsonStr.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let text = json["text"] as? String, !text.isEmpty {
                                
                                await MainActor.run {
                                    self?.receiveRemoteClipboard(text)
                                }
                            }
                        }
                    }
                } catch {
                    await MainActor.run {
                        self?.isSseConnected = false
                    }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }
        }
    }
    
    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    @MainActor
    public func receiveRemoteClipboard(_ text: String) {
        if text == lastSentToTablet || text == lastReceivedFromTablet {
            return
        }
        lastReceivedFromTablet = text
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastChangeCount = NSPasteboard.general.changeCount
        lastSyncedText = text
        syncDirection = "Moto Pad → Mac"
        postNotification(title: "📋 Clipboard Synced", body: "Copied from Moto Pad: \"\(text.prefix(50))\"")
    }
}
