import SwiftUI
import AppKit

public struct TransferHistoryView: View {
    @ObservedObject var history = HistoryStore.shared
    @ObservedObject var client = TransferClient.shared
    @ObservedObject var discovery = DeviceDiscoveryService.shared
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transfer History")
                    .font(.system(size: 14, weight: .bold))
                
                Spacer()
                
                if !history.items.isEmpty {
                    Button(action: {
                        history.clear()
                    }) {
                        Text("Clear All")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if history.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No transfers yet")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(history.items) { item in
                            historyRow(for: item)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    private func historyRow(for item: TransferItem) -> some View {
        HStack(spacing: 12) {
            statusIcon(for: item.status)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(item.formattedSize)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    
                    Text(item.targetFolder ?? item.category)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    
                    Text(timeAgo(from: item.timestamp))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                if FileManager.default.fileExists(atPath: item.localURL.path) {
                    Button(action: {
                        NSWorkspace.shared.activateFileViewerSelecting([item.localURL])
                    }) {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Show original file in Finder")
                    
                    Button(action: {
                        if let dev = discovery.selectedDevice {
                            client.startTransfer(item: item, target: dev)
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Send file again")
                    .disabled(client.isTransferring || !(discovery.selectedDevice?.isOnline ?? false))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
    }
    
    private func statusIcon(for status: TransferStatus) -> some View {
        switch status {
        case .completed:
            return Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed:
            return Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        case .cancelled:
            return Image(systemName: "slash.circle.fill").foregroundColor(.gray)
        case .transferring, .connecting, .hashing:
            return Image(systemName: "arrow.up.circle.fill").foregroundColor(.blue)
        case .idle:
            return Image(systemName: "circle").foregroundColor(.secondary)
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
