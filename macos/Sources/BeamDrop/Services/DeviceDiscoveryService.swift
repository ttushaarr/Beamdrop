import Foundation
import Network
import Combine

public class DeviceDiscoveryService: ObservableObject {
    public static let shared = DeviceDiscoveryService()
    
    @Published public var discoveredDevices: [PairedDevice] = []
    @Published public var selectedDevice: PairedDevice?
    @Published public var isSearching: Bool = false
    @Published public var currentSubnetHint: String = "192.168.1."
    
    private var browser: NWBrowser?
    private var pingTimer: Timer?
    private var pathMonitor: NWPathMonitor?
    private let pairedDevicesKey = "BeamDrop_PairedDevices"
    
    public init() {
        loadPersistedDevices()
        startDiscovery()
        startNetworkPathMonitoring()
        scanActiveSubnets()
        startPeriodicPing()
    }
    
    deinit {
        stopDiscovery()
        pingTimer?.invalidate()
        pathMonitor?.cancel()
    }
    
    // MARK: - Dynamic Active Subnet Detection
    
    public static func getActiveSubnetPrefixes() -> [String] {
        var orderedPrefixes: [String] = []
        var seen: Set<String> = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            
            // Require interface to be UP, RUNNING, and NOT Loopback
            guard (flags & (IFF_UP | IFF_RUNNING)) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            
            if addr.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                var addrCopy = ptr.pointee.ifa_addr.pointee
                getnameinfo(&addrCopy, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, 0, NI_NUMERICHOST)
                let ip = String(cString: hostname)
                let parts = ip.split(separator: ".").compactMap { Int($0) }
                if parts.count == 4 && ip != "127.0.0.1" {
                    let directPrefix = "\(parts[0]).\(parts[1]).\(parts[2])."
                    if !seen.contains(directPrefix) {
                        seen.insert(directPrefix)
                        orderedPrefixes.append(directPrefix)
                    }
                    
                    if let netmaskPtr = ptr.pointee.ifa_netmask {
                        var maskCopy = netmaskPtr.pointee
                        var maskHostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(&maskCopy, socklen_t(maskCopy.sa_len),
                                    &maskHostname, socklen_t(maskHostname.count),
                                    nil, 0, NI_NUMERICHOST)
                        let maskParts = String(cString: maskHostname).split(separator: ".").compactMap { Int($0) }
                        if maskParts.count == 4 && maskParts[2] < 255 {
                            let thirdByte = parts[2]
                            let maskThird = maskParts[2]
                            let startThird = thirdByte & maskThird
                            let endThird = min(startThird + (255 - maskThird), startThird + 15)
                            for t in startThird...endThird {
                                let p = "\(parts[0]).\(parts[1]).\(t)."
                                if !seen.contains(p) {
                                    seen.insert(p)
                                    orderedPrefixes.append(p)
                                }
                            }
                        }
                    }
                }
            }
        }
        return orderedPrefixes
    }

    public static func getArpNeighborIps() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-an"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let pattern = #"\((([0-9]{1,3}\.){3}[0-9]{1,3})\)"#
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let nsOutput = output as NSString
                    let matches = regex.matches(in: output, range: NSRange(location: 0, length: nsOutput.length))
                    return matches.map { nsOutput.substring(with: $0.range(at: 1)) }
                }
            }
        } catch {}
        return []
    }

    public func probeAndAddHost(_ host: String, session: URLSession? = nil) {
        guard let url = URL(string: "http://\(host):8765/api/v1/ping") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 0.8
        
        let activeSession = session ?? URLSession.shared
        activeSession.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil,
                  let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let deviceId = json["deviceId"] as? String {
                let name = (json["deviceName"] as? String) ?? "Android Device"
                DispatchQueue.main.async {
                    self.updateOrAddDevice(id: deviceId, name: name, host: host, port: 8765, isOnline: true)
                    print("[DISCOVERY] Found BeamDrop at \(host):8765 (\(name))")
                }
            }
        }.resume()
    }

    public func probeAdbDevices() {
        guard let adbPath = AdbService.findAdbPath() else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: adbPath)
            p.arguments = ["devices"]
            let pipe = Pipe()
            p.standardOutput = pipe
            try? p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8) ?? ""
            for line in out.components(separatedBy: "\n").dropFirst() {
                let parts = line.split(separator: "\t")
                if parts.count >= 2, parts[1].trimmingCharacters(in: .whitespaces) == "device" {
                    let serial = String(parts[0])
                    let ipProc = Process()
                    ipProc.executableURL = URL(fileURLWithPath: adbPath)
                    ipProc.arguments = ["-s", serial, "shell", "ip", "route"]
                    let ipPipe = Pipe()
                    ipProc.standardOutput = ipPipe
                    try? ipProc.run()
                    ipProc.waitUntilExit()
                    let ipData = ipPipe.fileHandleForReading.readDataToEndOfFile()
                    let ipOut = String(data: ipData, encoding: .utf8) ?? ""
                    if let match = ipOut.range(of: #"src (([0-9]{1,3}\.){3}[0-9]{1,3})"#, options: .regularExpression) {
                        let ip = String(ipOut[match]).replacingOccurrences(of: "src ", with: "").trimmingCharacters(in: .whitespaces)
                        if !ip.isEmpty {
                            DispatchQueue.main.async {
                                self?.probeAndAddHost(ip)
                            }
                        }
                    }
                    let fwdProc = Process()
                    fwdProc.executableURL = URL(fileURLWithPath: adbPath)
                    fwdProc.arguments = ["-s", serial, "forward", "tcp:8765", "tcp:8765"]
                    try? fwdProc.run()
                }
            }
        }
    }
    
    public func scanActiveSubnets() {
        let prefixes = Self.getActiveSubnetPrefixes()
        if let first = prefixes.first {
            DispatchQueue.main.async { self.currentSubnetHint = first }
        }
        
        guard !prefixes.isEmpty else { return }
        DispatchQueue.main.async { self.isSearching = true }
        
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 0.6
        config.timeoutIntervalForResource = 0.6
        let scanSession = URLSession(configuration: config)
        
        // 0. Immediately probe saved target IP if available
        let prefs = UserDefaults(suiteName: "com.beamdrop.BeamDrop") ?? UserDefaults.standard
        if let savedIp = prefs.string(forKey: "target_ip"), !savedIp.isEmpty {
            probeAndAddHost(savedIp, session: scanSession)
        }
        
        // 1. Immediately probe ARP neighbors (fastest lookup, capped to avoid socket flood)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let arpIps = Self.getArpNeighborIps()
            for ip in arpIps.prefix(80) {
                self?.probeAndAddHost(ip, session: scanSession)
            }
        }
        
        // 2. Query ADB devices and auto-forward port 8765
        probeAdbDevices()
        
        // 3. Sweep all active subnet blocks (primary block first)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            for prefix in prefixes {
                for i in 1...254 {
                    let host = "\(prefix)\(i)"
                    self.probeAndAddHost(host, session: scanSession)
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.isSearching = false
            }
        }
    }
    
    // MARK: - Network Switch Monitoring
    
    private func startNetworkPathMonitoring() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                print("[NETWORK] Active network path changed: \(path)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self?.scanActiveSubnets()
                }
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        self.pathMonitor = monitor
    }
    
    // MARK: - Bonjour mDNS Discovery
    
    public func startDiscovery() {
        guard browser == nil else { return }
        
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_beamdrop._tcp", domain: "local.")
        let newBrowser = NWBrowser(for: descriptor, using: parameters)
        
        newBrowser.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isSearching = true
                case .failed(let error):
                    print("NWBrowser failed: \(error)")
                    self?.isSearching = false
                case .cancelled:
                    self?.isSearching = false
                default:
                    break
                }
            }
        }
        
        newBrowser.browseResultsChangedHandler = { [weak self] results, changes in
            for result in results {
                self?.resolveEndpoint(result.endpoint)
            }
        }
        
        newBrowser.start(queue: .main)
        self.browser = newBrowser
        self.isSearching = true
    }
    
    public func stopDiscovery() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }
    
    private func resolveEndpoint(_ endpoint: NWEndpoint) {
        switch endpoint {
        case .service(let name, _, _, _):
            let connection = NWConnection(to: endpoint, using: .tcp)
            connection.stateUpdateHandler = { [weak self] state in
                if case .ready = state {
                    if let remoteEndpoint = connection.currentPath?.remoteEndpoint {
                        if case .hostPort(let host, let port) = remoteEndpoint {
                            let hostStr: String
                            switch host {
                            case .ipv4(let ip): hostStr = "\(ip)"
                            case .ipv6(let ip): hostStr = "\(ip)"
                            case .name(let n, _): hostStr = n
                            @unknown default: hostStr = "localhost"
                            }
                            self?.checkDevice(host: hostStr, port: Int(port.rawValue), hintName: name)
                        }
                    }
                    connection.cancel()
                }
            }
            connection.start(queue: .main)
        default:
            break
        }
    }
    
    public func addManualDevice(host: String, port: Int = 8765) {
        checkDevice(host: host, port: port, hintName: "Android Device")
    }
    
    public func checkDevice(host: String, port: Int, hintName: String = "Android Device") {
        guard let url = URL(string: "http://\(host):\(port)/api/v1/ping") else { return }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else {
                self?.markDeviceOffline(host: host)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let deviceId = json["deviceId"] as? String {
                    let deviceName = (json["deviceName"] as? String) ?? hintName
                    
                    DispatchQueue.main.async {
                        self.updateOrAddDevice(id: deviceId, name: deviceName, host: host, port: port, isOnline: true)
                    }
                }
            } catch {
                print("Failed to parse ping response: \(error)")
            }
        }.resume()
    }
    
    public static let fallbackAuthToken = "e71cae5964a44470a759c097719e8cbeb124845567d0462ba93aaf096581e13f"
    
    public func getSavedAuthToken() -> String {
        let prefs = UserDefaults(suiteName: "com.beamdrop.BeamDrop") ?? UserDefaults.standard
        if let token = prefs.string(forKey: "paired_token"), !token.isEmpty {
            return token
        }
        if let devToken = selectedDevice?.serverAuthToken, !devToken.isEmpty {
            return devToken
        }
        if let devToken = discoveredDevices.first(where: { !$0.serverAuthToken.isEmpty })?.serverAuthToken {
            return devToken
        }
        return Self.fallbackAuthToken
    }
    
    public func updateOrAddDevice(id: String, name: String, host: String, port: Int, isOnline: Bool) {
        var updatedDevice: PairedDevice?
        let defaultToken = getSavedAuthToken()
        
        if let idx = discoveredDevices.firstIndex(where: { $0.id == id }) {
            discoveredDevices[idx].name = name
            discoveredDevices[idx].host = host
            discoveredDevices[idx].port = port
            discoveredDevices[idx].isOnline = isOnline
            discoveredDevices[idx].lastSeen = Date()
            if discoveredDevices[idx].serverAuthToken.isEmpty {
                discoveredDevices[idx].serverAuthToken = defaultToken
            }
            discoveredDevices[idx].isPaired = true
            updatedDevice = discoveredDevices[idx]
        } else if let idx = discoveredDevices.firstIndex(where: { $0.host == host }) {
            discoveredDevices[idx].id = id
            discoveredDevices[idx].name = name
            discoveredDevices[idx].host = host
            discoveredDevices[idx].port = port
            discoveredDevices[idx].isOnline = isOnline
            discoveredDevices[idx].lastSeen = Date()
            if discoveredDevices[idx].serverAuthToken.isEmpty {
                discoveredDevices[idx].serverAuthToken = defaultToken
            }
            discoveredDevices[idx].isPaired = true
            updatedDevice = discoveredDevices[idx]
        } else {
            let device = PairedDevice(
                id: id,
                name: name,
                host: host,
                port: port,
                serverAuthToken: defaultToken,
                clientAuthToken: UUID().uuidString,
                lastSeen: Date(),
                isOnline: isOnline,
                isPaired: true
            )
            discoveredDevices.append(device)
            updatedDevice = device
        }
        
        if selectedDevice == nil || selectedDevice?.id == id || selectedDevice?.name == name {
            selectedDevice = updatedDevice
        }
        
        // Persist updated IP to preferences
        let prefs = UserDefaults(suiteName: "com.beamdrop.BeamDrop") ?? UserDefaults.standard
        prefs.set(host, forKey: "target_ip")
        prefs.set(port, forKey: "target_port")
        prefs.set(defaultToken, forKey: "paired_token")
        
        persistDevices()
        
        // Notify KDE Connect and Clipboard services about the new IP immediately
        KdeConnectService.shared.start()
        ClipboardSyncService.shared.startSseConnection()
    }
    
    private func markDeviceOffline(host: String) {
        DispatchQueue.main.async {
            if let idx = self.discoveredDevices.firstIndex(where: { $0.host == host }) {
                self.discoveredDevices[idx].isOnline = false
                if self.selectedDevice?.host == host {
                    self.selectedDevice?.isOnline = false
                }
            }
        }
    }
    
    private var consecutiveOfflinePings: Int = 0

    private func startPeriodicPing() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            for device in self.discoveredDevices {
                self.checkDevice(host: device.host, port: device.port, hintName: device.name)
            }
            if self.selectedDevice == nil || self.selectedDevice?.isOnline == false {
                self.consecutiveOfflinePings += 1
                if self.consecutiveOfflinePings >= 2 {
                    self.consecutiveOfflinePings = 0
                    self.scanActiveSubnets()
                }
            } else {
                self.consecutiveOfflinePings = 0
            }
        }
    }
    
    public func savePairedDevice(_ device: PairedDevice) {
        if let idx = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[idx] = device
        } else {
            discoveredDevices.append(device)
        }
        selectedDevice = device
        persistDevices()
    }
    
    public func unpairDevice(_ device: PairedDevice) {
        if let idx = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[idx].isPaired = false
            discoveredDevices[idx].serverAuthToken = ""
        }
        if selectedDevice?.id == device.id {
            selectedDevice?.isPaired = false
            selectedDevice?.serverAuthToken = ""
        }
        persistDevices()
    }
    
    private func persistDevices() {
        let prefs = UserDefaults(suiteName: "com.beamdrop.BeamDrop") ?? UserDefaults.standard
        if let data = try? JSONEncoder().encode(discoveredDevices) {
            prefs.set(data, forKey: pairedDevicesKey)
        }
    }
    
    private func loadPersistedDevices() {
        let prefs = UserDefaults(suiteName: "com.beamdrop.BeamDrop") ?? UserDefaults.standard
        let savedIp = prefs.string(forKey: "target_ip")
        if let data = prefs.data(forKey: pairedDevicesKey),
           var devices = try? JSONDecoder().decode([PairedDevice].self, from: data), !devices.isEmpty {
            for i in 0..<devices.count {
                if devices[i].serverAuthToken.isEmpty {
                    devices[i].serverAuthToken = Self.fallbackAuthToken
                }
                if let ip = savedIp, !ip.isEmpty, devices[i].host.hasPrefix("192.168.1.") || !ip.isEmpty {
                    devices[i].host = ip
                }
                devices[i].isPaired = true
            }
            self.discoveredDevices = devices
            self.selectedDevice = devices.first(where: { $0.isPaired }) ?? devices.first
            prefs.set(Self.fallbackAuthToken, forKey: "paired_token")
        } else {
            let defaultDevice = PairedDevice(
                id: "moto-pad-60-pro-f5bfb763",
                name: "Moto Pad 60 Pro",
                host: "192.168.1.7",
                port: 8765,
                serverAuthToken: Self.fallbackAuthToken,
                clientAuthToken: UUID().uuidString,
                lastSeen: Date(),
                isOnline: false,
                isPaired: true
            )
            self.discoveredDevices = [defaultDevice]
            self.selectedDevice = defaultDevice
            prefs.set(Self.fallbackAuthToken, forKey: "paired_token")
            persistDevices()
        }
    }
}
