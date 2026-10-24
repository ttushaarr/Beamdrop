import Foundation
import CryptoKit
import Combine
import UserNotifications

public class TransferClient: NSObject, ObservableObject, URLSessionTaskDelegate {
    public static let shared = TransferClient()
    
    @Published public var currentTransfer: TransferItem?
    @Published public var isTransferring: Bool = false
    @Published public var autoSendEnabled: Bool = false
    
    private var activeSession: URLSession?
    private var activeUploadTask: URLSessionUploadTask?
    private var lastSpeedCheckTime: Date?
    private var lastBytesSent: Int64 = 0
    private var cancellables = Set<AnyCancellable>()
    
    override public init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600 // Support large files up to an hour
        self.activeSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        
        requestNotificationPermission()
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    
    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    /// Calculates SHA-256 hash using streaming buffer (memory efficient for large files)
    public func computeSHA256(for url: URL, progress: @escaping (Double) -> Void) async throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }
        
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // 1 MB buffer
        var totalRead: Int64 = 0
        
        while true {
            let data = fileHandle.readData(ofLength: bufferSize)
            if data.isEmpty { break }
            hasher.update(data: data)
            totalRead += Int64(data.count)
            if fileSize > 0 {
                progress(Double(totalRead) / Double(fileSize))
            }
        }
        
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    public func startTransfer(item: TransferItem, target: PairedDevice, completion: ((Result<TransferItem, Error>) -> Void)? = nil) {
        guard !isTransferring else { return }
        
        var transfer = item
        transfer.status = .hashing
        self.currentTransfer = transfer
        self.isTransferring = true
        self.lastSpeedCheckTime = nil
        self.lastBytesSent = 0
        HistoryStore.shared.add(transfer)
        
        Task {
            do {
                // 1. Hash computation
                let hash = try await computeSHA256(for: transfer.localURL) { _ in }
                
                await MainActor.run {
                    var updated = self.currentTransfer ?? transfer
                    updated.sha256 = hash
                    updated.status = .connecting
                    self.currentTransfer = updated
                    HistoryStore.shared.update(updated)
                }
                
                guard let baseURL = target.baseURL else {
                    throw NSError(domain: "BeamDrop", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid target device URL"])
                }
                
                // 2. Transfer Init handshake
                let initURL = baseURL.appendingPathComponent("/api/v1/transfer/init")
                var initRequest = URLRequest(url: initURL)
                initRequest.httpMethod = "POST"
                initRequest.setValue("Bearer \(target.serverAuthToken)", forHTTPHeaderField: "Authorization")
                initRequest.setValue(target.clientAuthToken, forHTTPHeaderField: "X-BeamDrop-Sender-Id")
                initRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let transferId = UUID().uuidString
                let initPayload: [String: Any] = [
                    "transferId": transferId,
                    "fileName": transfer.fileName,
                    "fileSize": transfer.fileSize,
                    "mimeType": transfer.mimeType,
                    "sha256": hash,
                    "timestamp": Int(Date().timeIntervalSince1970)
                ]
                initRequest.httpBody = try JSONSerialization.data(withJSONObject: initPayload)
                
                let (initData, initResponse) = try await URLSession.shared.data(for: initRequest)
                guard let httpInit = initResponse as? HTTPURLResponse else {
                    throw NSError(domain: "BeamDrop", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
                }
                
                if httpInit.statusCode == 401 {
                    throw NSError(domain: "BeamDrop", code: 401, userInfo: [NSLocalizedDescriptionKey: "Tablet rejected authorization: Device not paired"])
                }
                guard httpInit.statusCode == 200 else {
                    let msg = String(data: initData, encoding: .utf8) ?? "HTTP \(httpInit.statusCode)"
                    throw NSError(domain: "BeamDrop", code: httpInit.statusCode, userInfo: [NSLocalizedDescriptionKey: "Tablet init failed: \(msg)"])
                }
                
                var resolvedName = transfer.fileName
                var targetFolder = transfer.category
                if let json = try? JSONSerialization.jsonObject(with: initData) as? [String: Any] {
                    if let rName = json["resolvedFileName"] as? String { resolvedName = rName }
                    if let tFolder = json["targetFolder"] as? String { targetFolder = tFolder }
                }
                
                await MainActor.run {
                    var updated = self.currentTransfer ?? transfer
                    updated.resolvedFileName = resolvedName
                    updated.targetFolder = targetFolder
                    updated.status = .transferring
                    self.currentTransfer = updated
                    HistoryStore.shared.update(updated)
                }
                
                // 3. Streaming Upload
                var uploadComponents = URLComponents(url: baseURL.appendingPathComponent("/api/v1/transfer/upload"), resolvingAgainstBaseURL: false)!
                uploadComponents.queryItems = [URLQueryItem(name: "transferId", value: transferId)]
                
                var uploadRequest = URLRequest(url: uploadComponents.url!)
                uploadRequest.httpMethod = "POST"
                uploadRequest.setValue("Bearer \(target.serverAuthToken)", forHTTPHeaderField: "Authorization")
                uploadRequest.setValue(target.clientAuthToken, forHTTPHeaderField: "X-BeamDrop-Sender-Id")
                uploadRequest.setValue("\(transfer.fileSize)", forHTTPHeaderField: "Content-Length")
                uploadRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                
                let task = self.activeSession?.uploadTask(with: uploadRequest, fromFile: transfer.localURL)
                self.activeUploadTask = task
                self.lastSpeedCheckTime = Date()
                self.lastBytesSent = 0
                task?.resume()
                
            } catch {
                await MainActor.run {
                    self.failCurrentTransfer(error: error.localizedDescription)
                    completion?(.failure(error))
                }
            }
        }
    }
    
    public func cancelTransfer() {
        activeUploadTask?.cancel()
        if var transfer = currentTransfer {
            transfer.status = .cancelled
            transfer.errorMessage = "Transfer cancelled by user"
            HistoryStore.shared.update(transfer)
            self.currentTransfer = transfer
        }
        self.isTransferring = false
        self.activeUploadTask = nil
    }
    
    private func failCurrentTransfer(error: String) {
        if var transfer = currentTransfer {
            transfer.status = .failed
            transfer.errorMessage = error
            HistoryStore.shared.update(transfer)
            self.currentTransfer = transfer
            postNotification(title: "Transfer Failed", body: "\(transfer.fileName): \(error)")
        }
        self.isTransferring = false
        self.activeUploadTask = nil
    }
    
    // MARK: - URLSessionTaskDelegate
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        DispatchQueue.main.async {
            guard var transfer = self.currentTransfer, self.isTransferring else { return }
            
            transfer.bytesSent = totalBytesSent
            
            let now = Date()
            if let lastTime = self.lastSpeedCheckTime {
                let interval = now.timeIntervalSince(lastTime)
                if interval >= 0.3 { // Smooth update every 300ms
                    let deltaBytes = totalBytesSent - self.lastBytesSent
                    let instantSpeed = Double(deltaBytes) / interval
                    
                    // Exponential smoothing for steady speed display
                    if transfer.speedBytesPerSec == 0 {
                        transfer.speedBytesPerSec = instantSpeed
                    } else {
                        transfer.speedBytesPerSec = (0.7 * transfer.speedBytesPerSec) + (0.3 * instantSpeed)
                    }
                    
                    let remainingBytes = transfer.fileSize - totalBytesSent
                    if transfer.speedBytesPerSec > 0 && remainingBytes > 0 {
                        transfer.estimatedTimeRemaining = Double(remainingBytes) / transfer.speedBytesPerSec
                    }
                    
                    self.lastSpeedCheckTime = now
                    self.lastBytesSent = totalBytesSent
                }
            } else {
                self.lastSpeedCheckTime = now
                self.lastBytesSent = totalBytesSent
            }
            
            self.currentTransfer = transfer
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            if let error = error as NSError? {
                if error.code == NSURLErrorCancelled {
                    return // Handled in cancelTransfer
                }
                self.failCurrentTransfer(error: error.localizedDescription)
                return
            }
            
            guard let response = task.response as? HTTPURLResponse else {
                self.failCurrentTransfer(error: "No response from tablet")
                return
            }
            
            if response.statusCode == 200 {
                if var transfer = self.currentTransfer {
                    transfer.status = .completed
                    transfer.bytesSent = transfer.fileSize
                    transfer.speedBytesPerSec = 0
                    transfer.estimatedTimeRemaining = 0
                    HistoryStore.shared.update(transfer)
                    self.currentTransfer = transfer
                    
                    let folderDesc = transfer.targetFolder ?? transfer.category
                    self.postNotification(title: "Transfer Complete", body: "\(transfer.fileName) saved to \(folderDesc) on tablet")
                }
                self.isTransferring = false
                self.activeUploadTask = nil
            } else {
                self.failCurrentTransfer(error: "Tablet returned error code \(response.statusCode)")
            }
        }
    }
}
