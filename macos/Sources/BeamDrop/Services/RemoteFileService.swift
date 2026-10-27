import Foundation
import AppKit

public struct RemoteFileItem: Identifiable, Codable, Hashable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let size: Int64
    public let lastModified: Int64
    public let mimeType: String?
}

public final class RemoteFileService: ObservableObject {
    public static let shared = RemoteFileService()
    
    @Published public var currentFolder: String = "Download"
    @Published public var files: [RemoteFileItem] = []
    @Published public var isLoading: Bool = false
    @Published public var statusMessage: String? = nil
    
    private let fallbackToken = "e71cae5964a44470a759c097719e8cbeb124845567d0462ba93aaf096581e13f"
    private let defaultHost = "192.168.1.7"
    private let defaultPort = 8765
    
    private init() {}
    
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
    
    public func fetchFolder(_ folder: String = "Download") async {
        await MainActor.run {
            self.isLoading = true
            self.currentFolder = folder
            self.statusMessage = nil
        }
        
        let host = getTargetHost()
        let port = getTargetPort()
        let token = getActiveToken()
        
        let encodedFolder = folder.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? folder
        guard let url = URL(string: "http://\(host):\(port)/api/v1/files/list?folder=\(encodedFolder)") else { return }
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 8
        
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let filesArray = json["files"] as? [[String: Any]] {
                    var parsed: [RemoteFileItem] = []
                    for f in filesArray {
                        let name = f["name"] as? String ?? "unknown"
                        let path = f["path"] as? String ?? name
                        let isDir = f["isDirectory"] as? Bool ?? false
                        let size = (f["size"] as? NSNumber)?.int64Value ?? 0
                        let modified = (f["lastModified"] as? NSNumber)?.int64Value ?? 0
                        let mime = f["mimeType"] as? String
                        parsed.append(RemoteFileItem(name: name, path: path, isDirectory: isDir, size: size, lastModified: modified, mimeType: mime))
                    }
                    await MainActor.run {
                        self.files = parsed
                        self.isLoading = false
                    }
                    return
                }
            }
        } catch {
            await MainActor.run {
                self.statusMessage = "Failed to list files: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
        
        await MainActor.run { self.isLoading = false }
    }
    
    public func downloadFile(_ item: RemoteFileItem) async -> URL? {
        await MainActor.run { self.statusMessage = "Downloading \(item.name)..." }
        
        let host = getTargetHost()
        let port = getTargetPort()
        let token = getActiveToken()
        
        let encodedPath = item.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? item.path
        guard let url = URL(string: "http://\(host):\(port)/api/v1/files/download?path=\(encodedPath)") else { return nil }
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 60
        
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                await MainActor.run { self.statusMessage = "Download failed" }
                return nil
            }
            
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            let saveDir = downloads.appendingPathComponent("BeamDrop", isDirectory: true)
            try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
            
            let destURL = saveDir.appendingPathComponent(item.name)
            try data.write(to: destURL)
            
            await MainActor.run {
                self.statusMessage = "✓ Saved to ~/Downloads/BeamDrop/\(item.name)"
                
                let script = """
                display notification "Saved to Downloads/BeamDrop/" with title "BeamDrop Download Complete" subtitle "\(item.name)"
                """
                var err: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&err)
                NSSound(named: "Glass")?.play()
            }
            return destURL
        } catch {
            await MainActor.run { self.statusMessage = "Error: \(error.localizedDescription)" }
            return nil
        }
    }
}
