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
    
    // OGP Metadata
    var ogTitle: String?
    var ogDescription: String?
    var ogImagePath: String?
    
    var isURL: Bool = false
    var isLoadingOGP: Bool = false
}

class ClipboardManager: ObservableObject {
// ... (omitting some middle part for brevity in replacement, but I must match exactly)
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
            let trimmedStr = str.trimmingCharacters(in: .whitespacesAndNewlines)
            var item = ClipboardItem(id: UUID(), date: Date(), type: .text, content: str, imagePath: nil)
            
            // Robust URL detection
            if let url = URL(string: trimmedStr), 
               let scheme = url.scheme?.lowercased(), 
               ["http", "https"].contains(scheme),
               url.host != nil {
                item.isURL = true
                item.isLoadingOGP = true
                insertItem(item)
                fetchOGP(for: item, url: url)
            } else {
                insertItem(item)
            }
        }
    }
    
    private func fetchOGP(for item: ClipboardItem, url: URL) {
        print("Fetching OGP for: \(url)")
        
        Task {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8.0 // 8 second timeout for the page
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                guard let html = String(data: data, encoding: .utf8) else { return }
                
                let title = self.extractMetaContent(html: html, property: "og:title")
                let description = self.extractMetaContent(html: html, property: "og:description")
                let imageURLString = self.extractMetaContent(html: html, property: "og:image")
                
                var localImageFilename: String?
                if let imageURLString = imageURLString, let imageURL = URL(string: imageURLString) {
                    localImageFilename = await downloadOGPImage(url: imageURL, itemId: item.id)
                }
                
                await MainActor.run {
                    if let index = self.history.firstIndex(where: { $0.id == item.id }) {
                        var updatedItem = self.history[index]
                        updatedItem.ogTitle = title
                        updatedItem.ogDescription = description
                        updatedItem.ogImagePath = localImageFilename
                        updatedItem.isLoadingOGP = false
                        self.history[index] = updatedItem
                        self.saveHistory()
                        print("Updated OGP for: \(url) - Found info: \(title != nil)")
                    }
                }
            } catch {
                print("OGP Fetch error for \(url): \(error.localizedDescription)")
                await MainActor.run {
                    if let index = self.history.firstIndex(where: { $0.id == item.id }) {
                        self.history[index].isLoadingOGP = false
                        self.saveHistory()
                    }
                }
            }
        }
    }
    
    private func downloadOGPImage(url: URL, itemId: UUID) async -> String? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0 // 5 second timeout for images
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let _ = NSImage(data: data) {
                let filename = "\(itemId.uuidString)_ogp.png"
                let fileURL = self.imagesDirectory.appendingPathComponent(filename)
                try data.write(to: fileURL)
                return filename
            }
        } catch {
            print("OGP Image download error: \(error.localizedDescription)")
        }
        return nil
    }
    
    private func extractMetaContent(html: String, property: String) -> String? {
        // More robust regex to handle:
        // 1. property="..." or name="..."
        // 2. content="..." appearing before or after the property/name attribute
        // 3. Different quote types and spacing
        
        let patterns = [
            "<meta\\s+[^>]*?(?:property|name)=[\"']\(property)[\"'][^>]*?content=[\"'](.*?)[\"']",
            "<meta\\s+[^>]*?content=[\"'](.*?)[\"'][^>]*?(?:property|name)=[\"']\(property)[\"']"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
               let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)) {
                if let swiftRange = Range(match.range(at: 1), in: html) {
                    // Decode HTML entities (basic)
                    return String(html[swiftRange])
                        .replacingOccurrences(of: "&amp;", with: "&")
                        .replacingOccurrences(of: "&quot;", with: "\"")
                        .replacingOccurrences(of: "&lt;", with: "<")
                        .replacingOccurrences(of: "&gt;", with: ">")
                }
            }
        }
        return nil
    }

    private func insertItem(_ item: ClipboardItem) {
        if item.type != .image {
            if let existingIndex = history.firstIndex(where: { $0.content == item.content && $0.type == item.type }) {
                let oldItem = history[existingIndex]
                if let ogPath = oldItem.ogImagePath {
                    try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(ogPath))
                }
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
            if let ogPath = removed.ogImagePath {
                let url = imagesDirectory.appendingPathComponent(ogPath)
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
            if let ogPath = item.ogImagePath {
                try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(ogPath))
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
    
    func ogImage(for item: ClipboardItem) -> NSImage? {
        guard let path = item.ogImagePath else { return nil }
        return NSImage(contentsOf: imagesDirectory.appendingPathComponent(path))
    }
}