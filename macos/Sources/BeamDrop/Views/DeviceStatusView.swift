import SwiftUI

public struct DeviceStatusView: View {
    @ObservedObject var discovery = DeviceDiscoveryService.shared
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 28, height: 28)
                
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(deviceName)
                        .font(.system(size: 13, weight: .semibold))
                    
                    if let dev = discovery.selectedDevice, dev.isPaired {
                        Text("PAIRED")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    } else {
                        Text("NOT PAIRED")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
                
                Text(statusSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { discovery.scanActiveSubnets() }) {
                if discovery.isSearching {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("Re-scan active Wi-Fi subnet for devices")
            
            if let dev = discovery.selectedDevice, dev.isOnline {
                Image(systemName: "wifi")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
            } else {
                Image(systemName: "wifi.slash")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    private var deviceName: String {
        discovery.selectedDevice?.name ?? "Moto Pad 60 Pro"
    }
    
    private var statusColor: Color {
        guard let dev = discovery.selectedDevice else {
            return .gray
        }
        if dev.isOnline && dev.isPaired {
            return .green
        } else if dev.isOnline && !dev.isPaired {
            return .orange
        } else {
            return .red
        }
    }
    
    private var statusSubtitle: String {
        guard let dev = discovery.selectedDevice else {
            return "Searching for tablet on Wi-Fi..."
        }
        if dev.isOnline {
            return "Connected via \(dev.host):\(dev.port)"
        } else {
            return "Tablet is offline or app not running"
        }
    }
}
