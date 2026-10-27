import SwiftUI

public class SettingsViewModel: ObservableObject {
    @Published public var hostInput: String = "192.168.1.7"
    @Published public var portInput: String = "8765"
    @Published public var pinInput: String = ""
    @Published public var selectedTab: Int = 0
    
    public init() {}
}

public struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    @ObservedObject var discovery = DeviceDiscoveryService.shared
    @ObservedObject var pairing = PairingService.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $vm.selectedTab) {
                Text("Device Pairing").tag(0)
                Text("Preferences & Folders").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if vm.selectedTab == 0 {
                        pairingTab
                    } else {
                        preferencesTab
                    }
                }
                .padding(20)
            }
        }
        .onAppear {
            discovery.scanActiveSubnets()
            if let dev = discovery.selectedDevice, !dev.host.isEmpty {
                self.vm.hostInput = dev.host
                self.vm.portInput = "\(dev.port)"
            } else if let first = discovery.discoveredDevices.first {
                self.vm.hostInput = first.host
                self.vm.portInput = "\(first.port)"
            } else {
                let hint = discovery.currentSubnetHint
                self.vm.hostInput = "\(hint)2"
            }
        }
    }
    
    private var pairingTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Step 1: Discovered / Target Device
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("1. Target Android Device")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Button(action: { discovery.scanActiveSubnets() }) {
                        HStack(spacing: 4) {
                            if discovery.isSearching {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "sparkle.magnifyingglass")
                            }
                            Text("Auto-Scan Active Subnet")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                if !discovery.discoveredDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Available devices on Wi-Fi (Click to select):")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        ForEach(discovery.discoveredDevices) { dev in
                            deviceSelectionRow(dev)
                        }
                    }
                    .padding(.bottom, 4)
                }
                
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("IP Address:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        TextField("e.g. \(discovery.currentSubnetHint)45", text: $vm.hostInput)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Port:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        TextField("8765", text: $vm.portInput)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(" ")
                            .font(.system(size: 11))
                        Button("Scan / Ping") {
                            let port = Int(vm.portInput) ?? 8765
                            discovery.addManualDevice(host: vm.hostInput, port: port)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            
            Divider()
            
            // Step 2: 6-Digit PIN Code
            VStack(alignment: .leading, spacing: 8) {
                Text("2. Enter 6-Digit Pairing PIN")
                    .font(.system(size: 13, weight: .bold))
                
                Text("Look at the BeamDrop app screen on your device (\(vm.hostInput.isEmpty ? "target device" : vm.hostInput)) and enter the 6-digit code shown there.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    TextField("123456", text: $vm.pinInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .frame(width: 140)
                    
                    Button(action: performPairing) {
                        if pairing.isPairing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        } else {
                            Text("Pair with Device")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pairing.isPairing || vm.hostInput.isEmpty || vm.pinInput.count < 6)
                }
                
                if let error = pairing.pairingError {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                    .padding(.top, 4)
                }
                
                if pairing.pairingSuccess {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Successfully paired with \(vm.hostInput)! One-click transfers are now active.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                    }
                    .padding(.top, 4)
                }
            }
            
            Divider()
            
            // Step 3: Paired Devices list
            VStack(alignment: .leading, spacing: 8) {
                Text("3. Paired Devices")
                    .font(.system(size: 13, weight: .bold))
                
                if discovery.discoveredDevices.isEmpty {
                    Text("No paired devices found.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(discovery.discoveredDevices) { device in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(.system(size: 12, weight: .semibold))
                                Text("\(device.host):\(device.port) • \(device.isPaired ? "Trusted" : "Unpaired")")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if device.isPaired {
                                Button("Revoke Trust") {
                                    discovery.unpairDevice(device)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
            }
        }
    }
    
    private var preferencesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Automatic Folder Mapping on Android")
                .font(.system(size: 13, weight: .bold))
            
            VStack(spacing: 10) {
                folderRow(
                    icon: "photo.fill",
                    color: .purple,
                    title: "Photos & Images",
                    desc: "JPG, PNG, WebP, HEIC, GIF, AVIF",
                    path: "Pictures/LaptopTransfer/",
                    gallery: "✓ Automatically indexed into Google Photos & Gallery"
                )
                
                folderRow(
                    icon: "film.fill",
                    color: .orange,
                    title: "Videos",
                    desc: "MP4, MKV, MOV, WEBM, AVI",
                    path: "Movies/LaptopTransfer/",
                    gallery: "✓ Automatically indexed into Gallery"
                )
                
                folderRow(
                    icon: "doc.fill",
                    color: .blue,
                    title: "Documents & Others",
                    desc: "PDF, ZIP, DOCX, Code files, etc.",
                    path: "Download/LaptopTransfer/",
                    gallery: "✓ Saved to standard Downloads with original names"
                )
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Security & Privacy")
                    .font(.system(size: 13, weight: .bold))
                
                VStack(alignment: .leading, spacing: 6) {
                    Label("Direct local Wi-Fi only (No cloud / external servers)", systemImage: "shield.lefthalf.filled")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Label("SHA-256 end-to-end checksum verification", systemImage: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Label("Zero prompt on tablet once paired", systemImage: "bolt.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func folderRow(icon: String, color: Color, title: String, desc: String, path: String, gallery: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(path)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                Text(gallery)
                    .font(.system(size: 10))
                    .foregroundColor(.green)
            }
            
            Spacer()
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func deviceSelectionRow(_ dev: PairedDevice) -> some View {
        let isSelected = vm.hostInput == dev.host
        return HStack(spacing: 10) {
            Image(systemName: dev.name.lowercased().contains("phone") ? "iphone" : "ipad")
                .foregroundColor(dev.isOnline ? .green : .secondary)
                .font(.system(size: 14))
            
            VStack(alignment: .leading, spacing: 1) {
                Text(dev.name)
                    .font(.system(size: 11, weight: .bold))
                Text("\(dev.host):\(dev.port) • \(dev.isPaired ? "Trusted" : "Unpaired")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Button("Selected ✓") {
                    vm.hostInput = dev.host
                    vm.portInput = "\(dev.port)"
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button("Select") {
                    vm.hostInput = dev.host
                    vm.portInput = "\(dev.port)"
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func performPairing() {
        let port = Int(vm.portInput) ?? 8765
        pairing.pair(withHost: vm.hostInput, port: port, pin: vm.pinInput) { result in
            switch result {
            case .success(let device):
                discovery.savePairedDevice(device)
            case .failure:
                break
            }
        }
    }
}
