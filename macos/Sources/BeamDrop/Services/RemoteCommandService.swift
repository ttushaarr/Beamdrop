import Foundation
import AppKit

public final class RemoteCommandService {
    public static let shared = RemoteCommandService()
    
    private var isRinging = false
    private var ringingProcess: Process?
    
    private init() {}
    
    public func handleCommand(_ cmd: KdeRemoteCommand) {
        switch cmd.command {
        case "lock_screen":
            lockScreen()
        case "sleep":
            sleepMac()
        case "screenshot":
            takeScreenshot()
        case "mute":
            MediaControlService.shared.toggleMute()
        case "empty_trash":
            emptyTrash()
        case "terminal":
            launchTerminal()
        case "ring_mac":
            ringMac()
        case "open_url":
            if let urlStr = cmd.url, let url = URL(string: urlStr) {
                openUrl(url)
            }
        default:
            break
        }
    }
    
    public func lockScreen() {
        DispatchQueue.global(qos: .userInitiated).async {
            // Lock screen using SACLockScreenImmediate or CGSession or pmset
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            proc.arguments = ["displaysleepnow"]
            try? proc.run()
        }
    }
    
    public func sleepMac() {
        let script = "tell application \"System Events\" to sleep"
        runAppleScript(script)
    }
    
    public func takeScreenshot() {
        DispatchQueue.global(qos: .userInitiated).async {
            let df = DateFormatter()
            df.dateFormat = "yyyyMMdd_HHmmss"
            let dateStr = df.string(from: Date())
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            let targetPath = desktop?.appendingPathComponent("Screenshot_\(dateStr).png").path ?? "/tmp/Screenshot_\(dateStr).png"
            
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            proc.arguments = ["-x", targetPath]
            try? proc.run()
        }
    }
    
    public func emptyTrash() {
        let script = "tell application \"Finder\" to empty trash"
        runAppleScript(script)
    }
    
    public func launchTerminal() {
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-a", "Terminal", NSHomeDirectory()]
            try? proc.run()
        }
    }
    
    public func openUrl(_ url: URL) {
        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
        }
    }
    
    public func ringMac() {
        guard !isRinging else { return }
        isRinging = true
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Unmute and max volume
            let script = """
            set volume output muted false
            set volume output volume 100
            """
            self?.runAppleScript(script)
            
            // Play loud alert sounds & voice locator
            for _ in 0..<5 {
                guard self?.isRinging == true else { break }
                let soundProc = Process()
                soundProc.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
                soundProc.arguments = ["/System/Library/Sounds/Ping.aiff"]
                try? soundProc.run()
                soundProc.waitUntilExit()
                
                let sayProc = Process()
                sayProc.executableURL = URL(fileURLWithPath: "/usr/bin/say")
                sayProc.arguments = ["-v", "Samantha", "Here is your MacBook!"]
                try? sayProc.run()
                sayProc.waitUntilExit()
            }
            
            self?.isRinging = false
        }
    }
    
    public func stopRingMac() {
        isRinging = false
    }
    
    private func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let script = NSAppleScript(source: source) {
                script.executeAndReturnError(&error)
            }
        }
    }
}
