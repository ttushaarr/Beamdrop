import Foundation

public class HistoryStore: ObservableObject {
    public static let shared = HistoryStore()
    
    @Published public var items: [TransferItem] = []
    
    private let fileURL: URL
    
    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("BeamDrop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("history.json")
        load()
    }
    
    public func add(_ item: TransferItem) {
        DispatchQueue.main.async {
            self.items.insert(item, at: 0)
            if self.items.count > 100 {
                self.items.removeLast()
            }
            self.save()
        }
    }
    
    public func update(_ item: TransferItem) {
        DispatchQueue.main.async {
            if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                self.items[index] = item
                self.save()
            }
        }
    }
    
    public func clear() {
        DispatchQueue.main.async {
            self.items.removeAll()
            self.save()
        }
    }
    
    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            self.items = try JSONDecoder().decode([TransferItem].self, from: data)
        } catch {
            print("Failed to load history: \(error)")
        }
    }
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save history: \(error)")
        }
    }
}
