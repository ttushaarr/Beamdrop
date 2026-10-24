import Foundation
import Network
import Combine

public class DeviceDiscoveryService: ObservableObject {
    public static let shared = DeviceDiscoveryService()
    
    @Published public var discoveredDevices: [PairedDevice] = []
    @Published public var selectedDevice: PairedDevice?
    @Published public var isSearching: Bool = false
    
    private var browser: NWBrowser?
    private var pingTimer: Timer?
    private let pairedDevicesKey = "BeamDrop_PairedDevices"
    
    public init() {
        loadPersistedDevices()
        startDiscovery()
        checkDevice(host: "192.168.1.7", port: 8765, hintName: "Moto Pad 60 Pro")
        scanLocalSubnet()
        startPeriodicPing()
    }
    
    public func scanLocalSubnet() {
        // Quick probe across local /24 subnet for tablets where router blocks mDNS
        DispatchQueue.global(qos: .utility).async {
            for i in 2...25 {
                let ip = "192.168.1.\(i)"
                self.checkDevice(host: ip, port: 8765, hintName: "Moto Pad 60 Pro")
            }
        }
    }
    
    deinit {
        stopDiscovery()
        pingTimer?.invalidate()
    }
    
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
            // Try resolving host/port via connection
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
        checkDevice(host: host, port: port, hintName: "Moto Pad 60 Pro")
    }
    
    public func checkDevice(host: String, port: Int, hintName: String = "Android Tablet") {
        guard let url = URL(string: "http://\(host):\(port)/api/v1/ping") else { return }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 3.0
        
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
    
    private func updateOrAddDevice(id: String, name: String, host: String, port: Int, isOnline: Bool) {
        if let idx = discoveredDevices.firstIndex(where: { $0.id == id || $0.host == host }) {
            discoveredDevices[idx].name = name
            discoveredDevices[idx].host = host
            discoveredDevices[idx].port = port
            discoveredDevices[idx].isOnline = isOnline
            discoveredDevices[idx].lastSeen = Date()
        } else {
            let device = PairedDevice(id: id, name: name, host: host, port: port, lastSeen: Date(), isOnline: isOnline)
            discoveredDevices.append(device)
        }
        
        if selectedDevice == nil || selectedDevice?.id == id {
            selectedDevice = discoveredDevices.first(where: { $0.id == id })
        }
        
        persistDevices()
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
    
    private func startPeriodicPing() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            for device in self.discoveredDevices {
                self.checkDevice(host: device.host, port: device.port, hintName: device.name)
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
        if let data = prefs.data(forKey: pairedDevicesKey),
           let devices = try? JSONDecoder().decode([PairedDevice].self, from: data), !devices.isEmpty {
            self.discoveredDevices = devices
            self.selectedDevice = devices.first(where: { $0.isPaired }) ?? devices.first
        } else {
            // Pre-populate paired Moto Pad 60 Pro so it is instantly available without re-pairing
            let defaultDevice = PairedDevice(
                id: "moto-pad-60-pro-f5bfb763",
                name: "Moto Pad 60 Pro",
                host: "192.168.1.7",
                port: 8765,
                serverAuthToken: "e71cae5964a44470a759c097719e8cbeb124845567d0462ba93aaf096581e13f",
                clientAuthToken: UUID().uuidString,
                lastSeen: Date(),
                isOnline: true,
                isPaired: true
            )
            self.discoveredDevices = [defaultDevice]
            self.selectedDevice = defaultDevice
            persistDevices()
        }
    }
}
