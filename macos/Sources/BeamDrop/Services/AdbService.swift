import Foundation

public final class AdbService: ObservableObject {
    public static let shared = AdbService()
    
    @Published public var isConnecting: Bool = false
    @Published public var lastOutput: String = ""
    @Published public var connectedDevices: [String] = []
    
    private init() {
        Task { await refreshConnectedDevices() }
    }
    
    public static func findAdbPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    @discardableResult
    private func runAdbCommand(arguments: [String]) async -> (exitCode: Int32, output: String) {
        guard let adbPath = Self.findAdbPath() else {
            return (1, "Error: adb binary not found in standard paths. Please install Android Platform Tools or Android Studio.")
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = arguments
        
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        process.environment = env
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, output)
        } catch {
            return (1, "Failed to run adb: \(error.localizedDescription)")
        }
    }
    
    public func connect(host: String, port: Int = 5555) async -> (success: Bool, message: String) {
        await MainActor.run {
            self.isConnecting = true
            self.lastOutput = "Connecting to \(host):\(port)..."
        }
        
        let (code, output) = await runAdbCommand(arguments: ["connect", "\(host):\(port)"])
        let isSuccess = code == 0 && output.lowercased().contains("connected") && !output.lowercased().contains("failed")
        
        await MainActor.run {
            self.isConnecting = false
            self.lastOutput = output
        }
        
        await refreshConnectedDevices()
        return (isSuccess, output)
    }
    
    public func pair(host: String, port: Int, code: String) async -> (success: Bool, message: String) {
        await MainActor.run {
            self.isConnecting = true
            self.lastOutput = "Pairing with \(host):\(port)..."
        }
        
        let (exitCode, output) = await runAdbCommand(arguments: ["pair", "\(host):\(port)", code])
        let isSuccess = exitCode == 0 && output.lowercased().contains("successfully paired")
        
        await MainActor.run {
            self.isConnecting = false
            self.lastOutput = output
        }
        
        return (isSuccess, output)
    }
    
    public func enableTcpip(port: Int = 5555) async -> (success: Bool, message: String) {
        await MainActor.run {
            self.isConnecting = true
            self.lastOutput = "Switching USB device to TCP/IP on port \(port)..."
        }
        
        let (code, output) = await runAdbCommand(arguments: ["tcpip", "\(port)"])
        let isSuccess = code == 0 && (output.contains("restarting") || output.contains("port"))
        
        await MainActor.run {
            self.isConnecting = false
            self.lastOutput = output.isEmpty ? "Restarted in TCP mode on port \(port)" : output
        }
        
        return (isSuccess, self.lastOutput)
    }
    
    public func disconnect(host: String, port: Int = 5555) async -> (success: Bool, message: String) {
        let (code, output) = await runAdbCommand(arguments: ["disconnect", "\(host):\(port)"])
        await refreshConnectedDevices()
        return (code == 0, output)
    }
    
    public func refreshConnectedDevices() async {
        let (_, output) = await runAdbCommand(arguments: ["devices"])
        let lines = output.components(separatedBy: "\n")
        var devices: [String] = []
        for line in lines.dropFirst() {
            let parts = line.split(separator: "\t")
            if parts.count >= 2, parts[1].trimmingCharacters(in: .whitespaces) == "device" {
                devices.append(String(parts[0]))
            }
        }
        
        await MainActor.run {
            self.connectedDevices = devices
        }
    }
    
    public func isHostConnected(_ host: String) -> Bool {
        return connectedDevices.contains { $0.contains(host) }
    }
}
