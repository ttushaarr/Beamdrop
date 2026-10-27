import Foundation
import AppKit
import Combine
import UserNotifications

public final class KdeConnectService: ObservableObject {
    public static let shared = KdeConnectService()
    
    @Published public var isConnected: Bool = false
    @Published public var isTabletRinging: Bool = false
    @Published public var recentNotifications: [KdeNotification] = []
    @Published public var lastSnapshotURL: URL?
    @Published public var isTakingSnapshot: Bool = false
    
    private var streamTask: Task<Void, Never>?
    private let fallbackToken = "e71cae5964a44470a759c097719e8cbeb124845567d0462ba93aaf096581e13f"
    private let defaultHost = "192.168.1.7"
    private let defaultPort = 8765
    
    private init() {}
    
    public func start() {
        startSseEventsStream()
        
        let token = getActiveToken()
        let host = getTargetHost()
        let port = getTargetPort()
        BatteryService.shared.startMonitoring(targetHost: host, port: port, token: token)
    }
    
    public func stop() {
        streamTask?.cancel()
        streamTask = nil
        BatteryService.shared.stopMonitoring()
        DispatchQueue.main.async { self.isConnected = false }
    }
    
    private func getActiveToken() -> String {
        let prefs = UserDefaults(suiteName: "com.beamdrop.BeamDrop") ?? .standard
        return prefs.string(forKey: "paired_token") ?? fallbackToken
    }
    
    private func getTargetHost() -> String {
        if let dev = DeviceDiscoveryService.shared.selectedDevice, !dev.host.isEmpty {
            return dev.host
        }
        let prefs = UserDefaults(suiteName: "com.beamdrop.BeamDrop") ?? .standard
        return prefs.string(forKey: "target_ip") ?? defaultHost
    }
    
    private func getTargetPort() -> Int {
        let prefs = UserDefaults(suiteName: "com.beamdrop.BeamDrop") ?? .standard
        let port = prefs.integer(forKey: "target_port")
        return port > 0 ? port : defaultPort
    }
    
    // MARK: - Persistent Multi-Event SSE Stream
    
    public func startSseEventsStream() {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                let host = self.getTargetHost()
                let port = self.getTargetPort()
                let token = self.getActiveToken()
                
                guard let url = URL(string: "http://\(host):\(port)/api/v1/events") else {
                    try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
                    continue
                }
                
                var request = URLRequest(url: url)
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 3600 // Keep stream alive
                
                do {
                    let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                        await MainActor.run { self.isConnected = true }
                        
                        var currentEventType = "message"
                        
                        for try await rawLine in asyncBytes.lines {
                            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                            if line.isEmpty {
                                currentEventType = "message"
                                continue
                            }
                            
                            if line.hasPrefix("event:") {
                                currentEventType = line.replacingOccurrences(of: "event:", with: "").trimmingCharacters(in: .whitespaces)
                                continue
                            }
                            
                            if line.hasPrefix("data:") {
                                let dataPayload = line.replacingOccurrences(of: "data:", with: "").trimmingCharacters(in: .whitespaces)
                                await self.dispatchIncomingEvent(type: currentEventType, payload: dataPayload)
                            }
                        }
                    }
                } catch {
                    // Stream closed or error
                }
                
                await MainActor.run { self.isConnected = false }
                try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
            }
        }
    }
    
    // MARK: - Event Dispatcher
    
    private func dispatchIncomingEvent(type: String, payload: String) async {
        guard let data = payload.data(using: .utf8) else { return }
        
        switch type {
        case "remote_input":
            if let input = try? JSONDecoder().decode(KdeRemoteInput.self, from: data) {
                RemoteInputService.shared.handleInput(input)
            }
            
        case "media_action":
            if let action = try? JSONDecoder().decode(KdeMediaAction.self, from: data) {
                MediaControlService.shared.handleMediaAction(action)
            }
            
        case "remote_command":
            if let cmd = try? JSONDecoder().decode(KdeRemoteCommand.self, from: data) {
                RemoteCommandService.shared.handleCommand(cmd)
            }
            
        case "ring_mac":
            RemoteCommandService.shared.ringMac()
            
        case "tablet_battery":
            if let battery = try? JSONDecoder().decode(KdeBatteryInfo.self, from: data) {
                await MainActor.run {
                    BatteryService.shared.tabletBattery = battery
                }
            }
            
        case "notification":
            if let notif = try? JSONDecoder().decode(KdeNotification.self, from: data) {
                await MainActor.run {
                    self.recentNotifications.insert(notif, at: 0)
                    if self.recentNotifications.count > 50 {
                        self.recentNotifications.removeLast()
                    }
                }
                self.showMacNotification(notif)
            }
            
        case "clipboard":
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                await ClipboardSyncService.shared.receiveRemoteClipboard(text)
            }
            
        default:
            break
        }
    }
    
    private func showMacNotification(_ notif: KdeNotification) {
        let appNameEsc = notif.appName.replacingOccurrences(of: "\"", with: "\\\"")
        let titleEsc = notif.title.replacingOccurrences(of: "\"", with: "\\\"")
        let textEsc = notif.text.replacingOccurrences(of: "\"", with: "\\\"")
        
        let script = """
        display notification "\(textEsc)" with title "\(appNameEsc)" subtitle "\(titleEsc)"
        """
        
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
            }
        }
    }
    
    // MARK: - Outgoing Actions to Tablet
    
    public func ringTablet() {
        let host = getTargetHost()
        let port = getTargetPort()
        let token = getActiveToken()
        
        guard let url = URL(string: "http://\(host):\(port)/api/v1/ring") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 5
        
        Task {
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    await MainActor.run { self.isTabletRinging = true }
                }
            } catch {}
        }
    }
    
    public func stopTabletRinging() {
        let host = getTargetHost()
        let port = getTargetPort()
        let token = getActiveToken()
        
        guard let url = URL(string: "http://\(host):\(port)/api/v1/ring/stop") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 5
        
        Task {
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    await MainActor.run { self.isTabletRinging = false }
                }
            } catch {}
        }
    }
    
    public func openUrlOnTablet(_ urlString: String) {
        let host = getTargetHost()
        let port = getTargetPort()
        let token = getActiveToken()
        
        guard let url = URL(string: "http://\(host):\(port)/api/v1/open-url") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 5
        
        let body = ["url": urlString]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        Task {
            _ = try? await URLSession.shared.data(for: req)
        }
    }
    
    public func replyToNotification(key: String, text: String) async -> Bool {
        let host = getTargetHost()
        let port = getTargetPort()
        let token = getActiveToken()
        
        guard let url = URL(string: "http://\(host):\(port)/api/v1/notifications/reply") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        
        let body = ["key": key, "replyText": text]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                print("[KDE] Successfully replied to notification \(key)")
                return true
            }
        } catch {
            print("[KDE] Error sending notification reply: \(error)")
        }
        return false
    }
    
    public func captureContinuitySnapshot() async throws -> URL? {
        let host = getTargetHost()
        let port = getTargetPort()
        let token = getActiveToken()
        
        guard let url = URL(string: "http://\(host):\(port)/api/v1/camera/snapshot") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        
        await MainActor.run { self.isTakingSnapshot = true }
        defer {
            Task { @MainActor in self.isTakingSnapshot = false }
        }
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
            throw NSError(domain: "BeamDropCamera", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "Failed to capture snapshot from Android device"])
        }
        
        let desktopDir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timeStr = formatter.string(from: Date())
        let destURL = desktopDir.appendingPathComponent("BeamDrop_Snapshot_\(timeStr).jpg")
        
        try data.write(to: destURL)
        
        await MainActor.run {
            self.lastSnapshotURL = destURL
            
            let script = """
            display notification "Saved to Desktop: \(destURL.lastPathComponent)" with title "BeamDrop Continuity Camera" subtitle "Snapshot Captured"
            """
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
            NSSound(named: "Glass")?.play()
        }
        
        return destURL
    }
}
