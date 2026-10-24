import SwiftUI
import AppKit
import UniformTypeIdentifiers

public class DropZoneViewModel: ObservableObject {
    @Published public var selectedFile: URL?
    @Published public var isTargeted: Bool = false
    @Published public var errorMessage: String?
    
    public init() {}
}

public struct DropZoneView: View {
    @StateObject private var vm = DropZoneViewModel()
    @ObservedObject var client = TransferClient.shared
    @ObservedObject var discovery = DeviceDiscoveryService.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            // Drag and Drop Area
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        vm.isTargeted ? Color.blue : Color.primary.opacity(0.15),
                        style: StrokeStyle(lineWidth: vm.isTargeted ? 2.5 : 1.5, dash: [8, 6])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(vm.isTargeted ? Color.blue.opacity(0.06) : Color(NSColor.controlBackgroundColor).opacity(0.5))
                    )
                
                VStack(spacing: 12) {
                    if let fileURL = vm.selectedFile {
                        selectedFileCard(for: fileURL)
                    } else {
                        emptyDropPrompt
                    }
                }
                .padding(24)
            }
            .frame(minHeight: 180)
            .onDrop(of: [.fileURL], isTargeted: $vm.isTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    if let url = url {
                        DispatchQueue.main.async {
                            self.handleFileSelection(url)
                        }
                    }
                }
                return true
            }
            
            // Workflow controls: Send Automatically Checkbox + Action Buttons
            HStack(spacing: 16) {
                Toggle(isOn: $client.autoSendEnabled) {
                    HStack(spacing: 4) {
                        Text("Send automatically on select")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }
                .toggleStyle(.checkbox)
                
                Spacer()
                
                Button(action: selectFileViaPanel) {
                    Label("Select File...", systemImage: "doc.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Button(action: sendCurrentFile) {
                    Label("Send Now", systemImage: "paperplane.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(vm.selectedFile == nil || client.isTransferring || !(discovery.selectedDevice?.isOnline ?? false))
            }
            
            if let error = vm.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(6)
            }
        }
    }
    
    private var emptyDropPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 38))
                .foregroundColor(.blue.opacity(0.8))
            
            Text("Drag & drop any file here")
                .font(.system(size: 14, weight: .semibold))
            
            Text("Images → Pictures/ • Videos → Movies/ • Other files → Download/")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
    
    private func selectedFileCard(for url: URL) -> some View {
        let item = TransferItem(url: url)
        return HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 44, height: 44)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(item.formattedSize)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(destinationBadge(for: item))
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(destinationColor(for: item).opacity(0.15))
                        .foregroundColor(destinationColor(for: item))
                        .cornerRadius(4)
                }
            }
            
            Spacer()
            
            Button(action: {
                self.vm.selectedFile = nil
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
    
    private func destinationBadge(for item: TransferItem) -> String {
        switch item.category {
        case "Pictures": return "Pictures/LaptopTransfer"
        case "Movies": return "Movies/LaptopTransfer"
        default: return "Download/LaptopTransfer"
        }
    }
    
    private func destinationColor(for item: TransferItem) -> Color {
        switch item.category {
        case "Pictures": return .purple
        case "Movies": return .orange
        default: return .blue
        }
    }
    
    private func handleFileSelection(_ url: URL) {
        self.vm.selectedFile = url
        self.vm.errorMessage = nil
        
        if client.autoSendEnabled {
            sendCurrentFile()
        }
    }
    
    private func selectFileViaPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a file to send to Moto Pad 60 Pro"
        panel.prompt = "Select"
        
        if panel.runModal() == .OK, let url = panel.url {
            handleFileSelection(url)
        }
    }
    
    private func sendCurrentFile() {
        guard let url = vm.selectedFile else { return }
        guard let device = discovery.selectedDevice else {
            self.vm.errorMessage = "No Android tablet selected or discovered"
            return
        }
        guard device.isOnline else {
            self.vm.errorMessage = "\(device.name) is currently offline"
            return
        }
        guard device.isPaired else {
            self.vm.errorMessage = "\(device.name) is not paired yet. Please pair in Settings."
            return
        }
        
        let item = TransferItem(url: url)
        client.startTransfer(item: item, target: device)
    }
}
