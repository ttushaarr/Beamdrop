import Foundation

public class PairingService: ObservableObject {
    public static let shared = PairingService()
    
    @Published public var isPairing: Bool = false
    @Published public var pairingError: String?
    @Published public var pairingSuccess: Bool = false
    
    public func pair(withHost host: String, port: Int = 8765, pin: String, completion: @escaping (Result<PairedDevice, Error>) -> Void) {
        guard let url = URL(string: "http://\(host):\(port)/api/v1/pair") else {
            let error = NSError(domain: "BeamDrop", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid host address"])
            self.pairingError = error.localizedDescription
            completion(.failure(error))
            return
        }
        
        self.isPairing = true
        self.pairingError = nil
        self.pairingSuccess = false
        
        let clientToken = UUID().uuidString
        let macId = Host.current().name ?? UUID().uuidString
        let macName = Host.current().localizedName ?? "MacBook Pro"
        
        let payload: [String: Any] = [
            "senderId": macId,
            "senderName": macName,
            "pairingSecret": pin.trimmingCharacters(in: .whitespacesAndNewlines),
            "clientAuthToken": clientToken
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            self.isPairing = false
            self.pairingError = error.localizedDescription
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isPairing = false
                
                if let error = error {
                    self?.pairingError = error.localizedDescription
                    completion(.failure(error))
                    return
                }
                
                guard let http = response as? HTTPURLResponse else {
                    let err = NSError(domain: "BeamDrop", code: 500, userInfo: [NSLocalizedDescriptionKey: "No response from tablet"])
                    self?.pairingError = err.localizedDescription
                    completion(.failure(err))
                    return
                }
                
                if http.statusCode == 403 {
                    let err = NSError(domain: "BeamDrop", code: 403, userInfo: [NSLocalizedDescriptionKey: "Incorrect PIN code entered"])
                    self?.pairingError = err.localizedDescription
                    completion(.failure(err))
                    return
                }
                
                guard http.statusCode == 200, let data = data else {
                    let err = NSError(domain: "BeamDrop", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Pairing failed with status \(http.statusCode)"])
                    self?.pairingError = err.localizedDescription
                    completion(.failure(err))
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let receiverId = json["receiverId"] as? String,
                       let serverAuthToken = json["serverAuthToken"] as? String {
                        let receiverName = (json["receiverName"] as? String) ?? "Moto Pad 60 Pro"
                        
                        let device = PairedDevice(
                            id: receiverId,
                            name: receiverName,
                            host: host,
                            port: port,
                            serverAuthToken: serverAuthToken,
                            clientAuthToken: clientToken,
                            lastSeen: Date(),
                            isOnline: true,
                            isPaired: true
                        )
                        
                        DeviceDiscoveryService.shared.savePairedDevice(device)
                        self?.pairingSuccess = true
                        completion(.success(device))
                    } else {
                        let err = NSError(domain: "BeamDrop", code: 500, userInfo: [NSLocalizedDescriptionKey: "Malformed pairing response from tablet"])
                        self?.pairingError = err.localizedDescription
                        completion(.failure(err))
                    }
                } catch {
                    self?.pairingError = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }.resume()
    }
}
