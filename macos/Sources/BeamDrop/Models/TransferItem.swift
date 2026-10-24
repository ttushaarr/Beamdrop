import Foundation
import SwiftUI
import AppKit

public enum TransferStatus: String, Codable {
    case idle = "IDLE"
    case hashing = "CALCULATING_CHECKSUM"
    case connecting = "CONNECTING"
    case transferring = "TRANSFERRING"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
}

public struct TransferItem: Identifiable, Codable {
    public let id: UUID
    public let localURL: URL
    public let fileName: String
    public let fileSize: Int64
    public let mimeType: String
    public var sha256: String?
    public var status: TransferStatus
    public var bytesSent: Int64
    public var speedBytesPerSec: Double
    public var estimatedTimeRemaining: TimeInterval?
    public var targetFolder: String?
    public var resolvedFileName: String?
    public var errorMessage: String?
    public var timestamp: Date

    public init(url: URL) {
        self.id = UUID()
        self.localURL = url
        self.fileName = url.lastPathComponent
        
        let resources = try? url.resourceValues(forKeys: [.fileSizeKey])
        self.fileSize = Int64(resources?.fileSize ?? 0)
        self.mimeType = TransferItem.mimeType(for: url)
        self.sha256 = nil
        self.status = .idle
        self.bytesSent = 0
        self.speedBytesPerSec = 0
        self.estimatedTimeRemaining = nil
        self.targetFolder = nil
        self.resolvedFileName = nil
        self.errorMessage = nil
        self.timestamp = Date()
    }

    public var progress: Double {
        guard fileSize > 0 else { return 0 }
        return min(1.0, Double(bytesSent) / Double(fileSize))
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    public var formattedSpeed: String {
        guard speedBytesPerSec > 0 else { return "0 KB/s" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return "\(formatter.string(fromByteCount: Int64(speedBytesPerSec)))/s"
    }

    public var formattedETA: String {
        guard let eta = estimatedTimeRemaining, eta > 0 else { return "--" }
        if eta < 60 {
            return "\(Int(eta))s remaining"
        } else {
            let minutes = Int(eta) / 60
            let seconds = Int(eta) % 60
            return "\(minutes)m \(seconds)s remaining"
        }
    }

    public var category: String {
        let ext = localURL.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "webp", "heic", "gif", "avif", "bmp", "tiff":
            return "Pictures"
        case "mp4", "mkv", "mov", "webm", "avi", "3gp":
            return "Movies"
        default:
            return "Downloads"
        }
    }

    public static func mimeType(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        switch pathExtension {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "gif": return "image/gif"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "mkv": return "video/x-matroska"
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        case "json": return "application/json"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }
}
