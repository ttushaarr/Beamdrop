import Foundation
import Network
import AppKit
import ScreenCaptureKit

public final class MacReceiverService: ObservableObject {
    public static let shared = MacReceiverService()
    
    @Published public var isRunning: Bool = false
    @Published public var lastReceivedFile: String?
    
    private var listener: NWListener?
    public let port: UInt16 = 8768
    
    private init() {}
    
    public func start() {
        guard listener == nil else { return }
        
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            let nwListener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            
            nwListener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        print("[RECEIVER] Mac receiver active on port \(self?.port ?? 8768)")
                    case .failed(let err):
                        print("[RECEIVER] Failed to bind receiver listener: \(err)")
                        self?.isRunning = false
                    case .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }
            
            nwListener.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }
            
            nwListener.start(queue: DispatchQueue.global(qos: .userInitiated))
            self.listener = nwListener
        } catch {
            print("[RECEIVER] Error starting receiver: \(error)")
        }
    }
    
    public func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async { self.isRunning = false }
    }
    
    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        
        var buffer = Data()
        var headersParsed = false
        var fileName = "received_file"
        var targetSubfolder = "Downloads"
        var contentLength: Int = 0
        var bodyStartIndex = 0
        var fileHandle: FileHandle?
        var destinationURL: URL?
        var bytesWritten: Int64 = 0
        
        func receiveNext() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
                guard let self = self else {
                    connection.cancel()
                    return
                }
                
                if let data = data, !data.isEmpty {
                    if !headersParsed {
                        buffer.append(data)
                        
                        // Look for \r\n\r\n header terminator
                        if let headerEndRange = buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) {
                            let headerData = buffer.subdata(in: 0..<headerEndRange.lowerBound)
                            bodyStartIndex = headerEndRange.upperBound
                            headersParsed = true
                            
                            if let headerStr = String(data: headerData, encoding: .utf8) {
                                let lines = headerStr.components(separatedBy: "\r\n")
                                if let firstLine = lines.first {
                                    if firstLine.hasPrefix("GET ") || firstLine.hasPrefix("HEAD ") {
                                        if firstLine.contains("/api/v1/ping") || firstLine.contains(" / ") {
                                            self.sendHttpResponse(connection: connection, statusCode: 200, body: "{\"status\":\"OK\",\"service\":\"MacReceiver\"}")
                                            return
                                        } else if firstLine.contains("/api/v1/screen/frame") {
                                            self.handleScreenFrame(connection: connection)
                                            return
                                        }
                                    } else if firstLine.hasPrefix("POST ") {
                                        if firstLine.contains("/api/v1/mac/unlock") {
                                            self.handleMacUnlock(connection: connection)
                                            return
                                        } else if firstLine.contains("/api/v1/screen/touch") {
                                            let body = buffer.count > bodyStartIndex ? buffer.subdata(in: bodyStartIndex..<buffer.count) : Data()
                                            self.handleScreenTouch(bodyData: body, connection: connection)
                                            return
                                        }
                                    }
                                }
                                for line in lines {
                                    let lower = line.lowercased()
                                    if lower.hasPrefix("x-file-name:") {
                                        let raw = String(line.dropFirst(12)).trimmingCharacters(in: .whitespaces)
                                        fileName = raw.removingPercentEncoding ?? raw
                                    } else if lower.hasPrefix("x-target-folder:") {
                                        targetSubfolder = String(line.dropFirst(16)).trimmingCharacters(in: .whitespaces)
                                    } else if lower.hasPrefix("content-length:") {
                                        contentLength = Int(String(line.dropFirst(15)).trimmingCharacters(in: .whitespaces)) ?? 0
                                    }
                                }
                            }
                            
                            // Prepare target folder
                            let saveDir = self.resolveDestinationDirectory(subfolder: targetSubfolder)
                            try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
                            
                            let safeFileName = self.getUniqueFileURL(directory: saveDir, fileName: fileName)
                            destinationURL = safeFileName
                            FileManager.default.createFile(atPath: safeFileName.path, contents: nil)
                            fileHandle = try? FileHandle(forWritingTo: safeFileName)
                            
                            // Write trailing initial body bytes if present
                            if bodyStartIndex < buffer.count {
                                let initialBody = buffer.subdata(in: bodyStartIndex..<buffer.count)
                                fileHandle?.write(initialBody)
                                bytesWritten += Int64(initialBody.count)
                            }
                        }
                    } else {
                        fileHandle?.write(data)
                        bytesWritten += Int64(data.count)
                    }
                }
                
                let isFinished = isComplete || (contentLength > 0 && bytesWritten >= Int64(contentLength))
                
                if isFinished {
                    fileHandle?.closeFile()
                    self.sendHttpResponse(connection: connection, statusCode: 200, body: "{\"status\":\"SUCCESS\"}")
                    
                    if let savedURL = destinationURL {
                        self.onFileSuccessfullyReceived(url: savedURL, fileName: fileName, fileSize: bytesWritten, targetFolder: targetSubfolder)
                    }
                    return
                }
                
                if error != nil {
                    fileHandle?.closeFile()
                    connection.cancel()
                    return
                }
                
                receiveNext()
            }
        }
        
        receiveNext()
    }
    
    private func handleScreenFrame(connection: NWConnection) {
        Task {
            var capturedImage: CGImage? = nil
            
            // 1. Try ScreenCaptureKit (macOS 12.3+, Sonoma & Sequoia native)
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                if let display = content.displays.first {
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let config = SCStreamConfiguration()
                    config.width = 1280
                    config.height = 800
                    config.showsCursor = true
                    capturedImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                }
            } catch {
                // ScreenCaptureKit fallback
            }
            
            // 2. Fallback to CGWindowListCreateImage if needed
            if capturedImage == nil, let screen = NSScreen.main {
                let rect = screen.frame
                capturedImage = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.nominalResolution])
            }
            
            guard let validImage = capturedImage else {
                self.sendHttpResponse(connection: connection, statusCode: 500, body: "{\"error\":\"Screen capture failed\"}")
                return
            }
            
            let rep = NSBitmapImageRep(cgImage: validImage)
            guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.45]) else {
                self.sendHttpResponse(connection: connection, statusCode: 500, body: "{\"error\":\"JPEG conversion failed\"}")
                return
            }
            
            let headerStr = "HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpegData.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
            if let headerData = headerStr.data(using: .utf8) {
                var fullData = headerData
                fullData.append(jpegData)
                connection.send(content: fullData, completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            } else {
                connection.cancel()
            }
        }
    }
    
    private func handleMacUnlock(connection: NWConnection) {
        DispatchQueue.main.async {
            let task = Process()
            task.launchPath = "/usr/bin/caffeinate"
            task.arguments = ["-u", "-t", "2"]
            try? task.run()
            
            let script = """
            display notification "Unlocked via Moto Pad 60 Pro Biometrics" with title "BeamDrop Biometric Unlock"
            """
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
            NSSound(named: "Glass")?.play()
        }
        sendHttpResponse(connection: connection, statusCode: 200, body: "{\"status\":\"UNLOCKED\"}")
    }
    
    private func handleScreenTouch(bodyData: Data, connection: NWConnection) {
        if let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
           let normX = json["x"] as? Double,
           let normY = json["y"] as? Double {
            DispatchQueue.main.async {
                guard let screen = NSScreen.main else { return }
                let screenW = screen.frame.width
                let screenH = screen.frame.height
                // Invert Y coordinate because macOS screen origin (0,0) is bottom-left while touch is top-left
                let targetPoint = CGPoint(x: normX * screenW, y: (1.0 - normY) * screenH)
                
                CGWarpMouseCursorPosition(targetPoint)
                
                let clickDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: targetPoint, mouseButton: .left)
                clickDown?.post(tap: .cghidEventTap)
                let clickUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: targetPoint, mouseButton: .left)
                clickUp?.post(tap: .cghidEventTap)
            }
        }
        sendHttpResponse(connection: connection, statusCode: 200, body: "{\"status\":\"OK\"}")
    }
    
    private func resolveDestinationDirectory(subfolder: String) -> URL {
        if subfolder.localizedCaseInsensitiveContains("pictures") || subfolder.localizedCaseInsensitiveContains("camera") {
            let pics = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
            return pics.appendingPathComponent("BeamDrop/Camera", isDirectory: true)
        }
        if subfolder.localizedCaseInsensitiveContains("sketch") || subfolder.localizedCaseInsensitiveContains("desktop") {
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        return downloads.appendingPathComponent("BeamDrop", isDirectory: true)
    }
    
    private func getUniqueFileURL(directory: URL, fileName: String) -> URL {
        var target = directory.appendingPathComponent(fileName)
        let ext = target.pathExtension
        let baseName = target.deletingPathExtension().lastPathComponent
        
        var counter = 1
        while FileManager.default.fileExists(atPath: target.path) {
            let newName = ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)"
            target = directory.appendingPathComponent(newName)
            counter += 1
        }
        return target
    }
    
    private func sendHttpResponse(connection: NWConnection, statusCode: Int, body: String) {
        let resp = "HTTP/1.1 \(statusCode) OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n\(body)"
        if let data = resp.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        } else {
            connection.cancel()
        }
    }
    
    private func onFileSuccessfullyReceived(url: URL, fileName: String, fileSize: Int64, targetFolder: String) {
        DispatchQueue.main.async {
            self.lastReceivedFile = fileName
            
            // If sketch or clipboard, copy directly to macOS Pasteboard
            if targetFolder.localizedCaseInsensitiveContains("clipboard") || targetFolder.localizedCaseInsensitiveContains("sketch") || fileName.localizedCaseInsensitiveContains("sketch") {
                if let img = NSImage(contentsOf: url) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([img])
                    print("[RECEIVER] Put received sketch/image directly onto macOS pasteboard!")
                }
            }
            
            // Add to history
            var item = TransferItem(url: url)
            item.status = .completed
            item.bytesSent = fileSize
            item.targetFolder = url.deletingLastPathComponent().path
            item.resolvedFileName = fileName
            HistoryStore.shared.add(item)
            
            // Native notification & chime
            let script = """
            display notification "Saved to \(url.deletingLastPathComponent().lastPathComponent)/" with title "BeamDrop Received" subtitle "\(fileName)"
            """
            var err: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&err)
            NSSound(named: "Glass")?.play()
        }
    }
}
