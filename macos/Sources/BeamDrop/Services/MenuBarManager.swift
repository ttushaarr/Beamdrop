import AppKit
import SwiftUI

public final class MenuBarManager: NSObject, NSDraggingDestination {
    public static let shared = MenuBarManager()
    
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    
    private override init() {
        super.init()
    }
    
    public func setupMenuBar() {
        guard statusItem == nil else { return }
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "BeamDrop")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover)
            button.target = self
            
            // Register button for drag & drop files
            button.registerForDraggedTypes([.fileURL])
        }
        
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 280, height: 260)
        pop.behavior = .transient
        pop.contentViewController = NSHostingController(rootView: MenuBarPopoverView())
        self.popover = pop
    }
    
    @objc public func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover?.contentViewController?.view.window?.makeKey()
        }
    }
    
    // MARK: - Drag & Drop directly onto the menu bar icon
    
    public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        if pboard.types?.contains(.fileURL) == true {
            statusItem?.button?.highlight(true)
            return .copy
        }
        return []
    }
    
    public func draggingExited(_ sender: NSDraggingInfo?) {
        statusItem?.button?.highlight(false)
    }
    
    public func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }
    
    public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        statusItem?.button?.highlight(false)
        let pboard = sender.draggingPasteboard
        
        guard let target = DeviceDiscoveryService.shared.selectedDevice ?? DeviceDiscoveryService.shared.discoveredDevices.first else {
            NSSound.beep()
            return false
        }
        
        guard let items = pboard.pasteboardItems else { return false }
        for item in items {
            if let urlString = item.string(forType: .fileURL), let url = URL(string: urlString) {
                let transferItem = TransferItem(url: url)
                TransferClient.shared.startTransfer(item: transferItem, target: target)
                return true
            }
        }
        return false
    }
}

public struct MenuBarPopoverView: View {
    @ObservedObject var discovery = DeviceDiscoveryService.shared
    @ObservedObject var battery = BatteryService.shared
    @ObservedObject var kde = KdeConnectService.shared
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.circle.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 16))
                    Text("BeamDrop")
                        .font(.system(size: 13, weight: .bold))
                }
                Spacer()
                if let dev = discovery.selectedDevice, dev.isOnline {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("Online").font(.system(size: 10, weight: .semibold)).foregroundColor(.green)
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle().fill(Color.red).frame(width: 6, height: 6)
                        Text("Offline").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
            }
            .padding(.bottom, 4)
            
            Divider()
            
            // Device & Battery Status
            VStack(alignment: .leading, spacing: 6) {
                Text(discovery.selectedDevice?.name ?? "Android Device")
                    .font(.system(size: 12, weight: .semibold))
                
                HStack(spacing: 12) {
                    if let tablet = battery.tabletBattery {
                        HStack(spacing: 3) {
                            Image(systemName: "ipad")
                            Text("\(tablet.percentage)%")
                            if tablet.isCharging { Image(systemName: "bolt.fill").foregroundColor(.green) }
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    }
                    
                    if let mac = battery.macBattery {
                        HStack(spacing: 3) {
                            Image(systemName: "laptopcomputer")
                            Text("\(mac.percentage)%")
                            if mac.isCharging { Image(systemName: "bolt.fill").foregroundColor(.green) }
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    }
                }
            }
            
            Divider()
            
            // Quick Actions
            VStack(spacing: 6) {
                Button(action: {
                    ScreenshotShortcutManager.shared.captureAndSendScreenshot()
                }) {
                    HStack {
                        Image(systemName: "camera.viewfinder").foregroundColor(.purple)
                        Text("Send Screenshot to Tablet (⌘⇧D)")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    selectAndSendFile()
                }) {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill").foregroundColor(.blue)
                        Text("Send File to Device...")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    if kde.isTabletRinging {
                        kde.stopTabletRinging()
                    } else {
                        kde.ringTablet()
                    }
                }) {
                    HStack {
                        Image(systemName: "speaker.wave.3.fill").foregroundColor(.red)
                        Text(kde.isTabletRinging ? "Stop Ringing Device" : "Ring Device")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    DeviceDiscoveryService.shared.scanActiveSubnets()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Scan Wi-Fi Subnet")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 11))
            
            Divider()
            
            // Bottom Bar
            HStack {
                Button("Open App Window") {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                .font(.system(size: 10))
                
                Spacer()
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 10))
                .foregroundColor(.red)
            }
        }
        .padding(14)
        .frame(width: 260)
    }
    
    private func selectAndSendFile() {
        guard let target = DeviceDiscoveryService.shared.selectedDevice ?? DeviceDiscoveryService.shared.discoveredDevices.first else {
            NSSound.beep()
            return
        }
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                let item = TransferItem(url: url)
                TransferClient.shared.startTransfer(item: item, target: target)
            }
        }
    }
}
