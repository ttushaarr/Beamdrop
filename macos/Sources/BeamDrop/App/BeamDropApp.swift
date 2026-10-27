import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        _ = DeviceDiscoveryService.shared
        _ = ClipboardSyncService.shared
        _ = KdeConnectService.shared
        _ = MacReceiverService.shared
        
        MacReceiverService.shared.start()
        MenuBarManager.shared.setupMenuBar()
        ClipboardSyncService.shared.startMonitoringMacPasteboard()
        ClipboardSyncService.shared.startSseConnection()
        KdeConnectService.shared.start()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Stay running in background for transfers
    }
}

@main
struct BeamDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        _ = DeviceDiscoveryService.shared
        _ = ClipboardSyncService.shared
        _ = KdeConnectService.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
