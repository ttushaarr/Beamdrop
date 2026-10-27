import SwiftUI

public class ContentViewModel: ObservableObject {
    @Published public var selectedTab: Int = 0
    public init() {}
}

public struct ContentView: View {
    @StateObject private var vm = ContentViewModel()
    @ObservedObject var client = TransferClient.shared
    @ObservedObject var discovery = DeviceDiscoveryService.shared
    @ObservedObject var clipboard = ClipboardSyncService.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header: Title & Device Status
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text("BeamDrop")
                            .font(.system(size: 16, weight: .bold))
                        Text("MacBook ⇄ Moto Pad 60 Pro")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Device Status Widget
                DeviceStatusView()
                    .frame(maxWidth: 320)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Live Clipboard Sync Status Bar
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 13))
                
                Text("Live Clipboard Sync")
                    .font(.system(size: 12, weight: .semibold))
                
                if let lastText = clipboard.lastSyncedText {
                    Text("• \(clipboard.syncDirection): \"\(lastText.prefix(32))\(lastText.count > 32 ? "..." : "")\"")
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.8))
                        .lineLimit(1)
                } else {
                    Text("• Copy on Mac or Tablet to instantly paste on the other device")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Toggle("", isOn: $clipboard.isSyncEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.08))
            
            Divider()
            
            // Tab Navigation Bar
            HStack {
                Picker("", selection: $vm.selectedTab) {
                    Label("Send File", systemImage: "arrow.up.circle.fill").tag(0)
                    Label("Remote Files", systemImage: "folder.fill").tag(1)
                    Label("KDE Connect", systemImage: "ipad.and.arrow.forward").tag(2)
                    Label("History", systemImage: "clock.fill").tag(3)
                    Label("Settings", systemImage: "gearshape.fill").tag(4)
                }
                .pickerStyle(.segmented)
                .frame(width: 540)
                
                Spacer()
                
                if discovery.isSearching {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                        Text("Scanning Wi-Fi...")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            
            Divider()
            
            // Content based on tab
            ScrollView {
                VStack(spacing: 16) {
                    if vm.selectedTab == 0 {
                        sendTab
                    } else if vm.selectedTab == 1 {
                        RemoteFileBrowserView()
                    } else if vm.selectedTab == 2 {
                        KdeConnectView()
                    } else if vm.selectedTab == 3 {
                        TransferHistoryView()
                    } else {
                        SettingsView()
                    }
                }
                .padding(18)
            }
        }
        .frame(minWidth: 640, minHeight: 540)
        .onAppear {
            ClipboardSyncService.shared.startMonitoringMacPasteboard()
            ClipboardSyncService.shared.startSseConnection()
            KdeConnectService.shared.start()
        }
    }
    
    private var sendTab: some View {
        VStack(spacing: 16) {
            // Main File Drop & Selection Zone
            DropZoneView()
            
            // Live Transfer Monitor (Progress, Speed, ETA, Cancel/Retry)
            TransferProgressView()
            
            // Compact Recent Transfers Preview
            TransferHistoryView()
        }
    }
}
