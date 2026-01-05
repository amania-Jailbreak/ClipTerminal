import SwiftUI
import AppKit
import Combine

enum ClipboardItemType: String, Codable {
    case text
    case image
    case file
}

struct ClipboardItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let date: Date
    let type: ClipboardItemType
    let content: String // Text content or File URL path
    let imagePath: String? // Local filename for cached images
    
    // Metadata
    var fileSize: Int64?
    var width: CGFloat?
    var height: CGFloat?
}

class ClipboardManager: ObservableObject {
    @Published var history: [ClipboardItem] = []
    private var lastChangeCount: Int = 0
    private var timer: Timer?
    
    private let maxHistoryCount = 100
    private let fileManager = FileManager.default
    
    // Paths
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private var historyFileURL: URL {
        documentsDirectory.appendingPathComponent("history.json")
    }
    
    private var imagesDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("images")
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    
    public init() {
        loadHistory()
        checkClipboard()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    deinit {
        timer?.invalidate()
    }
    
    // MARK: - Clipboard Monitoring
    
    func checkClipboard() {
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount == lastChangeCount { return }
        lastChangeCount = pasteboard.changeCount
        
        // 1. Check for File URL
        if let types = pasteboard.types, types.contains(.fileURL),
           let urlString = pasteboard.string(forType: .fileURL),
           let url = URL(string: urlString) {
            
            var item = ClipboardItem(id: UUID(), date: Date(), type: .file, content: url.path, imagePath: nil)
            if let attrs = try? fileManager.attributesOfItem(atPath: url.path) {
                item.fileSize = attrs[.size] as? Int64
            }
            insertItem(item)
            return
        }
        
        // 2. Check for Image
        if let types = pasteboard.types, types.contains(.png) || types.contains(.tiff) {
            let type: NSPasteboard.PasteboardType = types.contains(.png) ? .png : .tiff
            if let data = pasteboard.data(forType: type), let nsImage = NSImage(data: data) {
                let id = UUID()
                let filename = "\(id.uuidString).png"
                let fileURL = imagesDirectory.appendingPathComponent(filename)
                
                do {
                    try data.write(to: fileURL)
                    var item = ClipboardItem(id: id, date: Date(), type: .image, content: "Image", imagePath: filename)
                    item.fileSize = Int64(data.count)
                    item.width = nsImage.size.width
                    item.height = nsImage.size.height
                    insertItem(item)
                } catch {
                    print("Failed to save image: \(error)")
                }
                return
            }
        }
        
        // 3. Check for String (Text)
        if let str = pasteboard.string(forType: .string) {
            let item = ClipboardItem(id: UUID(), date: Date(), type: .text, content: str, imagePath: nil)
            insertItem(item)
        }
    }
    
    private func insertItem(_ item: ClipboardItem) {
        if item.type != .image {
            if let existingIndex = history.firstIndex(where: { $0.content == item.content && $0.type == item.type }) {
                history.remove(at: existingIndex)
            }
        }
        
        history.insert(item, at: 0)
        
        if history.count > maxHistoryCount {
            let removed = history.removeLast()
            if let path = removed.imagePath {
                let url = imagesDirectory.appendingPathComponent(path)
                try? fileManager.removeItem(at: url)
            }
        }
        saveHistory()
    }
    
    func copyToClipboard(item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.type {
        case .text:
            pasteboard.setString(item.content, forType: .string)
        case .file:
            let url = URL(fileURLWithPath: item.content)
            pasteboard.writeObjects([url as NSPasteboardWriting])
        case .image:
            if let path = item.imagePath {
                let url = imagesDirectory.appendingPathComponent(path)
                if let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
                    pasteboard.writeObjects([image])
                }
            }
        }
    }
    
    func clearHistory() {
        for item in history {
            if let path = item.imagePath {
                try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(path))
            }
        }
        history.removeAll()
        saveHistory()
    }
    
    private func saveHistory() {
        try? JSONEncoder().encode(history).write(to: historyFileURL)
    }
    
    private func loadHistory() {
        if let data = try? Data(contentsOf: historyFileURL) {
            history = (try? JSONDecoder().decode([ClipboardItem].self, from: data)) ?? []
        }
    }
    
    func image(for item: ClipboardItem) -> NSImage? {
        guard let path = item.imagePath else { return nil }
        return NSImage(contentsOf: imagesDirectory.appendingPathComponent(path))
    }
}