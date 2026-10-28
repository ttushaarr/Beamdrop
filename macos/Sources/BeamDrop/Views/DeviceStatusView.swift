import SwiftUI

public struct DeviceStatusView: View {
    @ObservedObject var discovery = DeviceDiscoveryService.shared
    @State private var showPopover: Bool = false
    @State private var manualIp: String = ""
    
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
            
            Button(action: { showPopover.toggle() }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Configure Target IP / Network")
            .popover(isPresented: $showPopover) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Target Device Connection")
                        .font(.system(size: 13, weight: .bold))
                    
                    Text("Enter the IP address shown at the top of the BeamDrop Android app screen:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        TextField("e.g. 10.102.8.250", text: $manualIp)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                        
                        Button("Connect") {
                            let ip = manualIp.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !ip.isEmpty {
                                discovery.probeAndAddHost(ip)
                                showPopover = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(manualIp.isEmpty)
                    }
                    
                    if !discovery.discoveredDevices.isEmpty {
                        Divider()
                        Text("Discovered Devices:")
                            .font(.system(size: 11, weight: .semibold))
                        ForEach(discovery.discoveredDevices) { dev in
                            Button(action: {
                                discovery.selectedDevice = dev
                                manualIp = dev.host
                                discovery.probeAndAddHost(dev.host)
                                showPopover = false
                            }) {
                                HStack {
                                    Circle().fill(dev.isOnline ? Color.green : Color.gray).frame(width: 8, height: 8)
                                    Text("\(dev.name) (\(dev.host))")
                                        .font(.system(size: 11))
                                    Spacer()
                                    if discovery.selectedDevice?.host == dev.host {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Divider()
                    
                    Button(action: {
                        discovery.scanActiveSubnets()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Full Subnet & ARP Sweep")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(14)
                .frame(width: 300)
                .onAppear {
                    manualIp = discovery.selectedDevice?.host ?? UserDefaults(suiteName: "com.beamdrop.BeamDrop")?.string(forKey: "target_ip") ?? ""
                }
            }
            
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
