import SwiftUI
import AppKit

import SwiftUI
import AppKit

public class KdeConnectViewModel: ObservableObject {
    @Published public var urlToOpen: String = ""
    @Published public var showUrlSuccess: Bool = false
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
                    Text(kde.isConnected ? "KDE Connect Stream Active" : "Connecting to Moto Pad...")
                        .font(.system(size: 15, weight: .bold))
                    Text(kde.isConnected ? "Bidirectional remote control, notifications, & battery sync active" : "Ensure tablet is on same Wi-Fi with BeamDrop open")
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
                        Text("Tablet Battery")
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
                            .foregroundColor(.indigo)
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
                        Text("Detecting...")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
            }
            
            // Find My Device (Ring Tablet) Action Card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundColor(.red)
                    Text("Find My Device")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                }
                
                Text("Play a loud alarm on your Moto Pad 60 Pro to locate it, even if tablet sound is muted.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    if kde.isTabletRinging {
                        Button(action: { kde.stopTabletRinging() }) {
                            HStack {
                                Image(systemName: "stop.circle.fill")
                                Text("Stop Ringing Tablet")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else {
                        Button(action: { kde.ringTablet() }) {
                            HStack {
                                Image(systemName: "bell.badge.fill")
                                Text("Ring Moto Pad 60 Pro")
                            }
                            .frame(maxWidth: .infinity)
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
            
            // Mirrored Android Notifications Feed
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
                            .padding(10)
                            .background(Color(NSColor.windowBackgroundColor))
                            .cornerRadius(8)
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
