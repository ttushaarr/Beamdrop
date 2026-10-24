import SwiftUI

public struct TransferProgressView: View {
    @ObservedObject var client = TransferClient.shared
    
    public init() {}
    
    public var body: some View {
        if let item = client.currentTransfer, client.isTransferring || item.status == .failed || item.status == .cancelled || item.status == .completed {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    fileIcon(for: item.fileName)
                        .frame(width: 36, height: 36)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.fileName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        
                        HStack(spacing: 6) {
                            Text(statusText(for: item))
                                .font(.system(size: 11))
                                .foregroundColor(statusColor(for: item))
                            
                            if let folder = item.targetFolder {
                                Text("•")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text(folder)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    if client.isTransferring {
                        Button(action: {
                            client.cancelTransfer()
                        }) {
                            Text("Cancel")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                    } else if item.status == .failed {
                        Button(action: {
                            if let dev = DeviceDiscoveryService.shared.selectedDevice {
                                client.startTransfer(item: item, target: dev)
                            }
                        }) {
                            Text("Retry")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                
                // Progress Bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 8)
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, min(geometry.size.width * CGFloat(item.progress), geometry.size.width)), height: 8)
                            .animation(.linear(duration: 0.2), value: item.progress)
                    }
                }
                .frame(height: 8)
                
                // Stats row
                HStack {
                    Text("\(Int(item.progress * 100))%")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("(\(ByteCountFormatter.string(fromByteCount: item.bytesSent, countStyle: .file)) of \(item.formattedSize))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if client.isTransferring && item.speedBytesPerSec > 0 {
                        Text(item.formattedSpeed)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.blue)
                        
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        
                        Text(item.formattedETA)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                if let error = item.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .padding(.top, 2)
                }
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    private func fileIcon(for name: String) -> some View {
        let ext = (name as NSString).pathExtension.lowercased()
        let iconName: String
        let color: Color
        switch ext {
        case "jpg", "jpeg", "png", "webp", "heic", "gif":
            iconName = "photo.fill"
            color = .purple
        case "mp4", "mov", "mkv", "avi":
            iconName = "film.fill"
            color = .orange
        case "pdf":
            iconName = "doc.text.fill"
            color = .red
        case "zip", "tar", "gz":
            iconName = "archivebox.fill"
            color = .blue
        default:
            iconName = "doc.fill"
            color = .blue
        }
        
        return Image(systemName: iconName)
            .font(.system(size: 24))
            .foregroundColor(color)
    }
    
    private func statusText(for item: TransferItem) -> String {
        switch item.status {
        case .idle: return "Ready"
        case .hashing: return "Verifying checksum..."
        case .connecting: return "Handshaking with tablet..."
        case .transferring: return "Transferring to Moto Pad..."
        case .completed: return "Transfer completed successfully"
        case .failed: return "Transfer failed"
        case .cancelled: return "Transfer cancelled"
        }
    }
    
    private func statusColor(for item: TransferItem) -> Color {
        switch item.status {
        case .completed: return .green
        case .failed, .cancelled: return .red
        default: return .blue
        }
    }
}
