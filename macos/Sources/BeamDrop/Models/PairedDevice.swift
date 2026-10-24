import Foundation

public struct PairedDevice: Identifiable, Codable, Equatable {
    public let id: String
    public var name: String
    public var host: String
    public var port: Int
    public var serverAuthToken: String
    public var clientAuthToken: String
    public var lastSeen: Date
    public var isOnline: Bool
    public var isPaired: Bool

    public init(
        id: String,
        name: String,
        host: String,
        port: Int = 8765,
        serverAuthToken: String = "",
        clientAuthToken: String = UUID().uuidString,
        lastSeen: Date = Date(),
        isOnline: Bool = false,
        isPaired: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.serverAuthToken = serverAuthToken
        self.clientAuthToken = clientAuthToken
        self.lastSeen = lastSeen
        self.isOnline = isOnline
        self.isPaired = isPaired
    }

    public var baseURL: URL? {
        URL(string: "http://\(host):\(port)")
    }
}
