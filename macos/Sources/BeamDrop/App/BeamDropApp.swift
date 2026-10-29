import SwiftUI
import AppKit

public class AppDelegate: NSObject, NSApplicationDelegate {
    public static var mainWindow: NSWindow?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
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
        ScreenshotShortcutManager.shared.start()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.showMainWindow()
        }
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }
    
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Stay running in background for transfers
    }
    
    public func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        if let win = Self.mainWindow, win.isVisible {
            win.makeKeyAndOrderFront(nil)
            win.orderFrontRegardless()
            return
        }
        
        if let win = Self.mainWindow {
            win.makeKeyAndOrderFront(nil)
            win.orderFrontRegardless()
            return
        }
        
        for win in NSApp.windows where win.canBecomeMain {
            Self.mainWindow = win
            win.isReleasedWhenClosed = false
            win.makeKeyAndOrderFront(nil)
            win.orderFrontRegardless()
            return
        }
        
        // Host window directly if not yet created or restored by SwiftUI WindowGroup
        let win = NSWindow(
            contentRect: NSRect(x: 140, y: 140, width: 880, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.center()
        win.title = "BeamDrop"
        win.contentView = NSHostingView(rootView: ContentView())
        win.isReleasedWhenClosed = false
        Self.mainWindow = win
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
    }
}

@main
struct BeamDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        _ = DeviceDiscoveryService.shared
        _ = ClipboardSyncService.shared
        _ = KdeConnectService.shared
        _ = ScreenshotShortcutManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    (NSApp.delegate as? AppDelegate)?.showMainWindow()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandMenu("Actions") {
                Button("Send Screenshot to Tablet (⌘⇧D)") {
                    ScreenshotShortcutManager.shared.captureAndSendScreenshot()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Solve Question on Screen with Gemini (⌘⇧X)") {
                    ScreenshotShortcutManager.shared.captureAndSendForAiSolve()
                }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            }
        }
    }
}
