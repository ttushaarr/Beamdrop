import Foundation
import IOKit.ps

public final class BatteryService: ObservableObject {
    public static let shared = BatteryService()
    
    @Published public var macBattery: KdeBatteryInfo?
    @Published public var tabletBattery: KdeBatteryInfo?
    
    private var timerTask: Task<Void, Never>?
    
    private init() {
        refreshMacBattery()
    }
    
    public func startMonitoring(targetHost: String = "192.168.1.7", port: Int = 8765, token: String) {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshMacBattery()
                let host = DeviceDiscoveryService.shared.selectedDevice?.host ?? targetHost
                let currentPort = DeviceDiscoveryService.shared.selectedDevice?.port ?? port
                if let battery = self?.macBattery {
                    await self?.pushMacBatteryToTablet(battery, host: host, port: currentPort, token: token)
                }
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000) // Every 30 seconds
            }
        }
    }
    
    public func stopMonitoring() {
        timerTask?.cancel()
        timerTask = nil
    }
    
    public func refreshMacBattery() {
        if let info = getMacBatteryFromIOKit() {
            DispatchQueue.main.async { self.macBattery = info }
            return
        }
        
        // Fallback to pmset command
        if let info = getMacBatteryFromPmset() {
            DispatchQueue.main.async { self.macBattery = info }
        }
    }
    
    private func getMacBatteryFromIOKit() -> KdeBatteryInfo? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef], !sources.isEmpty else { return nil }
        
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            
            if let cur = desc[kIOPSCurrentCapacityKey as String] as? Int,
               let max = desc[kIOPSMaxCapacityKey as String] as? Int, max > 0 {
                let percent = Int((Double(cur) / Double(max)) * 100.0)
                let isCharging = (desc[kIOPSIsChargingKey as String] as? Bool) ?? false
                return KdeBatteryInfo(percentage: percent, isCharging: isCharging)
            }
        }
        return nil
    }
    
    private func getMacBatteryFromPmset() -> KdeBatteryInfo? {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        proc.arguments = ["-g", "batt"]
        proc.standardOutput = pipe
        
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            
            // Format example: "... 85%; AC attached; not charging ..." or "85%; charging; ..."
            let regex = try NSRegularExpression(pattern: "(\\d{1,3})%")
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            if let match = regex.firstMatch(in: output, range: range),
               let matchRange = Range(match.range(at: 1), in: output),
               let percent = Int(output[matchRange]) {
                let isCharging = output.localizedCaseInsensitiveContains("charging") && !output.localizedCaseInsensitiveContains("not charging")
                return KdeBatteryInfo(percentage: percent, isCharging: isCharging)
            }
        } catch {
            return nil
        }
        return nil
    }
    
    private func pushMacBatteryToTablet(_ battery: KdeBatteryInfo, host: String, port: Int, token: String) async {
        guard let url = URL(string: "http://\(host):\(port)/api/v1/mac/battery") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5
        
        let body: [String: Any] = [
            "percentage": battery.percentage,
            "isCharging": battery.isCharging
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        _ = try? await URLSession.shared.data(for: request)
    }
}
