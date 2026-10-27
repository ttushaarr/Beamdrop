import SwiftUI
import AppKit

public class KdeConnectViewModel: ObservableObject {
    @Published public var urlToOpen: String = ""
    @Published public var showUrlSuccess: Bool = false
    @Published public var snapshotError: String? = nil
    public init() {}
}

public struct KdeConnectView: View {
    @StateObject private var vm = KdeConnectViewModel()
    @ObservedObject var kde = KdeConnectService.shared
    @ObservedObject var battery = BatteryService.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 20) {
            // Hero Status Banner
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(kde.isConnected ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: kde.isConnected ? "link.circle.fill" : "link.badge.plus")
                        .font(.system(size: 22))
                        .foregroundColor(kde.isConnected ? .green : .orange)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(kde.isConnected ? "KDE Connect Stream Active" : "Connecting to Android Device...")
                        .font(.system(size: 15, weight: .bold))
                    Text(kde.isConnected ? "Bidirectional remote control, notifications, camera & battery sync active" : "Ensure tablet is on same Wi-Fi with BeamDrop open")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if kde.isConnected {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Live SSE")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            // Battery Status Row
            HStack(spacing: 14) {
                // Tablet Battery Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "ipad.landscape")
                            .foregroundColor(.blue)
                        Text("Android Battery")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        if battery.tabletBattery?.isCharging == true {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 11))
                        }
                    }
                    
                    if let tablet = battery.tabletBattery {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(tablet.percentage)%")
                                .font(.system(size: 24, weight: .bold))
                            Text(tablet.isCharging ? "Charging ⚡" : "On Battery")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Connecting...")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                
                // Mac Battery Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "laptopcomputer")
                            .foregroundColor(.purple)
                        Text("MacBook Battery")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        if battery.macBattery?.isCharging == true {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 11))
                        }
                    }
                    
                    if let mac = battery.macBattery {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(mac.percentage)%")
                                .font(.system(size: 24, weight: .bold))
                            Text(mac.isCharging ? "Charging ⚡" : "On Battery")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("--%")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
            }
            
            // Continuity Camera Card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "camera.fill")
                        .foregroundColor(.cyan)
                    Text("Continuity Camera / Live Capture")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                }
                
                HStack(spacing: 12) {
                    Button(action: {
                        Task {
                            vm.snapshotError = nil
                            do {
                                _ = try await kde.captureContinuitySnapshot()
                            } catch {
                                await MainActor.run {
                                    vm.snapshotError = error.localizedDescription
                                }
                            }
                        }
                    }) {
                        HStack {
                            if kde.isTakingSnapshot {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Snapping...")
                            } else {
                                Image(systemName: "camera.aperture")
                                Text("Take Photo from Android")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(kde.isTakingSnapshot)
                    
                    if let snapshotURL = kde.lastSnapshotURL {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([snapshotURL])
                        }
                        .buttonStyle(.bordered)
                        
                        Text("Saved: \(snapshotURL.lastPathComponent)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                if let err = vm.snapshotError {
                    Text("Error: \(err)")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            // Find My Device (Ring Tablet) Card
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundColor(.red)
                    Text("Find My Device")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                }
                
                HStack {
                    Text("Lost your tablet under a couch or in another room? Sound full-volume alarm.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if kde.isTabletRinging {
                        Button(action: { kde.stopTabletRinging() }) {
                            HStack {
                                Image(systemName: "stop.circle.fill")
                                Text("Stop Alarm")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else {
                        Button(action: { kde.ringTablet() }) {
                            HStack {
                                Image(systemName: "bell.badge.fill")
                                Text("Ring Android Device")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            // Send URL to Tablet Card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "safari.fill")
                        .foregroundColor(.blue)
                    Text("Send Web Link to Tablet")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                }
                
                HStack {
                    TextField("Enter URL (e.g. https://youtube.com)", text: $vm.urlToOpen)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Open on Tablet") {
                        let raw = vm.urlToOpen.trimmingCharacters(in: .whitespaces)
                        let target = raw.hasPrefix("http") ? raw : "https://\(raw)"
                        kde.openUrlOnTablet(target)
                        vm.urlToOpen = ""
                        vm.showUrlSuccess = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            vm.showUrlSuccess = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.urlToOpen.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                
                if vm.showUrlSuccess {
                    Text("✓ Web page opened instantly on tablet!")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            // Mirrored Android Notifications Feed with Quick Reply
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "bell.fill")
                        .foregroundColor(.purple)
                    Text("Mirrored Notifications (\(kde.recentNotifications.count))")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    if !kde.recentNotifications.isEmpty {
                        Button("Clear") {
                            kde.recentNotifications.removeAll()
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                    }
                }
                
                if kde.recentNotifications.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "bell.slash")
                                .foregroundColor(.secondary)
                            Text("No incoming notifications yet")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 16)
                        Spacer()
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(kde.recentNotifications.prefix(5)) { notif in
                            NotificationRowView(notif: notif, kde: kde)
                        }
                    }
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
    }
}

public struct NotificationRowView: View {
    let notif: KdeNotification
    let kde: KdeConnectService
    @State private var replyText: String = ""
    @State private var isSendingReply: Bool = false
    @State private var replySent: Bool = false
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "app.badge.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.purple)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(notif.appName)
                            .font(.system(size: 11, weight: .bold))
                        Spacer()
                        Text(Date(timeIntervalSince1970: TimeInterval(notif.timestamp / 1000)), style: .time)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    Text(notif.title)
                        .font(.system(size: 11, weight: .semibold))
                    Text(notif.text)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            // Inline Quick Reply for notifications supporting RemoteInput
            if notif.canReply == true, let key = notif.key, !key.isEmpty {
                HStack(spacing: 8) {
                    TextField("Quick Reply...", text: $replyText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                    
                    Button(action: {
                        let text = replyText.trimmingCharacters(in: .whitespaces)
                        guard !text.isEmpty else { return }
                        isSendingReply = true
                        Task {
                            let ok = await kde.replyToNotification(key: key, text: text)
                            await MainActor.run {
                                isSendingReply = false
                                if ok {
                                    replySent = true
                                    replyText = ""
                                }
                            }
                        }
                    }) {
                        if isSendingReply {
                            ProgressView().scaleEffect(0.6)
                        } else if replySent {
                            Image(systemName: "checkmark")
                                .foregroundColor(.green)
                        } else {
                            Text("Reply")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty || isSendingReply)
                }
                .padding(.leading, 34)
            }
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}
