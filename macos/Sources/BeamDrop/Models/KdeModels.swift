import Foundation

public struct KdeBatteryInfo: Codable, Equatable {
    public let percentage: Int
    public let isCharging: Bool
    
    public init(percentage: Int, isCharging: Bool) {
        self.percentage = percentage
        self.isCharging = isCharging
    }
}

public struct KdeRemoteInput: Codable {
    public let type: String // "move", "click", "scroll", "key", "text"
    public let dx: Float?
    public let dy: Float?
    public let button: String? // "left", "right", "double"
    public let key: String? // "Left", "Right", "Up", "Down", "Return", "Backspace", "Space", "Escape", "Tab", "F5", "b"
    public let text: String?
}

public struct KdeMediaAction: Codable {
    public let action: String // "play_pause", "next", "prev", "volume_set", "mute", "volume_up", "volume_down"
    public let volume: Float?
}

public struct KdeRemoteCommand: Codable {
    public let command: String // "lock_screen", "sleep", "screenshot", "mute", "empty_trash", "terminal", "ring_mac", "open_url"
    public let url: String?
}

public struct KdeNotification: Codable, Identifiable {
    public var id: String { "\(appName)_\(timestamp)" }
    public let appName: String
    public let title: String
    public let text: String
    public let timestamp: Int64
}
