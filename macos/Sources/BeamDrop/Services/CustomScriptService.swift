import Foundation

public struct CustomScript: Identifiable, Codable, Equatable {
    public let id: String
    public var name: String
    public var command: String
    public var icon: String
    public var workDir: String?
    
    public init(id: String = UUID().uuidString, name: String, command: String, icon: String = "⚡", workDir: String? = nil) {
        self.id = id
        self.name = name
        self.command = command
        self.icon = icon
        self.workDir = workDir
    }
}

public final class CustomScriptService: ObservableObject {
    public static let shared = CustomScriptService()
    
    private let prefsKey = "BeamDrop_CustomScripts_v1"
    @Published public var scripts: [CustomScript] = []
    @Published public var lastExecutionOutput: String = ""
    @Published public var isExecuting: Bool = false
    
    private init() {
        loadScripts()
    }
    
    public func loadScripts() {
        let prefs = UserDefaults(suiteName: "com.beamdrop.BeamDrop") ?? UserDefaults.standard
        if let data = prefs.data(forKey: prefsKey),
           let saved = try? JSONDecoder().decode([CustomScript].self, from: data),
           !saved.isEmpty {
            self.scripts = saved
        } else {
            // Default starter scripts
            self.scripts = [
                CustomScript(name: "Git Status", command: "cd ~/Desktop && git status", icon: "🐙"),
                CustomScript(name: "Docker Status", command: "docker ps 2>&1 || echo 'Docker daemon not active'", icon: "🐳"),
                CustomScript(name: "Clear Dev Caches", command: "rm -rf ~/Library/Caches/com.apple.dt.Xcode/* 2>/dev/null && echo 'Xcode cache cleared!'", icon: "🧹"),
                CustomScript(name: "System Hardware Load", command: "top -l 1 | head -n 12", icon: "🖥️"),
                CustomScript(name: "Free Dev Ports (3000, 8080)", command: "lsof -ti:3000,8080 | xargs kill -9 2>/dev/null; echo 'Ports 3000 & 8080 freed!'", icon: "⚡"),
                CustomScript(name: "Play Alert Chime", command: "afplay /System/Library/Sounds/Glass.aiff && echo 'Played Mac Chime'", icon: "🎵")
            ]
            saveScripts()
        }
    }
    
    public func saveScripts() {
        let prefs = UserDefaults(suiteName: "com.beamdrop.BeamDrop") ?? UserDefaults.standard
        if let data = try? JSONEncoder().encode(scripts) {
            prefs.set(data, forKey: prefsKey)
        }
    }
    
    public func addOrUpdateScript(_ script: CustomScript) {
        if let idx = scripts.firstIndex(where: { $0.id == script.id }) {
            scripts[idx] = script
        } else {
            scripts.append(script)
        }
        saveScripts()
    }
    
    public func deleteScript(id: String) {
        scripts.removeAll { $0.id == id }
        saveScripts()
    }
    
    public func executeScript(id: String) async -> (exitCode: Int32, output: String) {
        guard let script = scripts.first(where: { $0.id == id }) else {
            return (1, "Script with ID \(id) not found")
        }
        return await executeRawCommand(script.command, workDir: script.workDir)
    }
    
    public func executeRawCommand(_ command: String, workDir: String? = nil) async -> (exitCode: Int32, output: String) {
        await MainActor.run {
            self.isExecuting = true
            self.lastExecutionOutput = "Running: \(command)..."
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        
        if let wd = workDir, !wd.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: (wd as NSString).expandingTildeInPath)
        } else {
            process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        }
        
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + NSHomeDirectory() + "/.cargo/bin:" + (env["PATH"] ?? "")
        process.environment = env
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let status = process.terminationStatus
                    
                    DispatchQueue.main.async {
                        self.isExecuting = false
                        self.lastExecutionOutput = output.isEmpty ? "(Command completed with exit code \(status))" : output
                    }
                    continuation.resume(returning: (status, output.isEmpty ? "(Exit code \(status))" : output))
                } catch {
                    DispatchQueue.main.async {
                        self.isExecuting = false
                        self.lastExecutionOutput = "Execution failed: \(error.localizedDescription)"
                    }
                    continuation.resume(returning: (1, error.localizedDescription))
                }
            }
        }
    }
}
