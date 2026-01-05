import SwiftUI
import AppKit
import Combine

struct ContentView: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    @State private var selectedItemId: UUID?
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @AppStorage("autoPaste") private var autoPaste: Bool = false
    
    var filteredHistory: [ClipboardItem] {
        if searchText.isEmpty {
            return clipboardManager.history
        } else {
            return clipboardManager.history.filter {
                $0.content.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var selectedItem: ClipboardItem? {
        guard let id = selectedItemId else { return nil }
        return clipboardManager.history.first(where: { $0.id == id })
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Pane: History List
            VStack(spacing: 0) {
                // Search Bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                    
                    Button(action: {
                        AppDelegate.shared?.openSettings()
                    }) {
                        Image(systemName: "gearshape")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(.ultraThinMaterial)
                
                Divider()
                
                // List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredHistory) { item in
                                ClipboardItemRow(item: item, isSelected: selectedItemId == item.id)
                                    .id(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedItemId = item.id
                                    }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: selectedItemId) { _, newValue in
                        if let newValue {
                            withAnimation(.snappy(duration: 0.1)) {
                                proxy.scrollTo(newValue, anchor: .center)
                            }
                        }
                    }
                }
            }
            .frame(width: 250)
            
            Divider()
            
            // MARK: - Right Pane: Detail View
            VStack(spacing: 0) {
                if let item = selectedItem {
                    DetailView(item: item)
                } else {
                    VStack {
                        Image(systemName: "clipboard")
                            .font(.system(size: 40))
                            .foregroundStyle(.quaternary)
                        Text("Select an item to view details")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.05))
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 16))
        .frame(width: 800, height: 500)
        .cornerRadius(16)
        .onAppear {
            isSearchFocused = true
            selectedItemId = filteredHistory.first?.id
            
            // Global Key Monitor for this Window
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 53: // Esc
                    NSApp.hide(nil)
                    return nil
                    
                case 125: // Down Arrow
                    moveSelection(direction: 1)
                    return nil
                    
                case 126: // Up Arrow
                    moveSelection(direction: -1)
                    return nil
                    
                case 48: // Tab
                    // Shift+Tab -> Up, Tab -> Down
                    let direction = event.modifierFlags.contains(.shift) ? -1 : 1
                    moveSelection(direction: direction)
                    return nil
                    
                case 36: // Enter
                    if let selectedId = selectedItemId,
                       let item = filteredHistory.first(where: { $0.id == selectedId }) {
                        copyAndClose(item: item)
                        return nil
                    }
                    
                default:
                    return event
                }
                return event
            }
        }
        .onChange(of: searchText) { _, _ in
            selectedItemId = filteredHistory.first?.id
        }
    }
    
    private func moveSelection(direction: Int) {
        guard !filteredHistory.isEmpty else { return }
        let currentId = selectedItemId ?? filteredHistory.first?.id
        guard let currentIndex = filteredHistory.firstIndex(where: { $0.id == currentId }) else {
            selectedItemId = filteredHistory.first?.id
            return
        }
        
        let newIndex = max(0, min(filteredHistory.count - 1, currentIndex + direction))
        selectedItemId = filteredHistory[newIndex].id
    }
    
    private func copyAndClose(item: ClipboardItem) {
        clipboardManager.copyToClipboard(item: item)
        NSApp.hide(nil)
        
        if autoPaste {
            // Delay to allow window to hide and previous app to focus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                simulatePaste()
            }
        }
    }
    
    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let kVK_ANSI_V: CGKeyCode = 0x09
        let cmdKey = CGEventFlags.maskCommand
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: kVK_ANSI_V, keyDown: true)
        keyDown?.flags = cmdKey
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: kVK_ANSI_V, keyDown: false)
        keyUp?.flags = cmdKey
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

// MARK: - Detail View

struct DetailView: View {
    let item: ClipboardItem
    @EnvironmentObject var clipboardManager: ClipboardManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(item.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { clipboardManager.copyToClipboard(item: item) }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding()
            .background(.white.opacity(0.05))
            
            Divider()
            
            // Content Area
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if item.type == .image {
                        // Image Preview
                        if let nsImage = clipboardManager.image(for: item) {
                            VStack(alignment: .center) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 250) // Smaller preview
                                    .cornerRadius(8)
                                    .shadow(radius: 4)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top)
                        }
                        
                        // Metadata Grid
                        VStack(spacing: 1) {
                            infoRow(label: "Filename", value: item.imagePath ?? "N/A")
                            infoRow(label: "Dimensions", value: dimensionsString)
                            infoRow(label: "File Size", value: fileSizeString)
                        }
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(8)
                        .padding(.horizontal)
                        
                    } else if item.type == .file {
                        VStack(spacing: 1) {
                            infoRow(label: "Name", value: URL(fileURLWithPath: item.content).lastPathComponent)
                            infoRow(label: "Full Path", value: item.content)
                            infoRow(label: "File Size", value: fileSizeString)
                        }
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(8)
                        .padding()
                        
                    } else {
                        // Text & OGP
                        VStack(alignment: .leading, spacing: 16) {
                            
                            // OGP Section
                            if item.isURL {
                                if item.isLoadingOGP {
                                    HStack {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("Fetching link details...")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding()
                                    .background(Color.primary.opacity(0.05))
                                    .cornerRadius(10)
                                    .padding(.horizontal)
                                    .padding(.top)
                                } else if item.ogTitle != nil || item.ogDescription != nil || item.ogImagePath != nil {
                                    // OGP Card (Show existing OGP data)
                                    VStack(alignment: .leading, spacing: 0) {
                                        if let nsImage = clipboardManager.ogImage(for: item) {
                                            Image(nsImage: nsImage)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(height: 150)
                                                .clipped()
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 6) {
                                            if let title = item.ogTitle {
                                                Text(title)
                                                    .font(.headline)
                                                    .lineLimit(2)
                                                    .foregroundStyle(.primary)
                                            }
                                            
                                            if let desc = item.ogDescription {
                                                Text(desc)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(3)
                                            }
                                            
                                            Text(item.content)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                        }
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.primary.opacity(0.05))
                                    }
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                    )
                                    .padding(.horizontal)
                                    .padding(.top)
                                } else {
                                    // URL but no OGP found
                                    HStack {
                                        Image(systemName: "link.badge.plus")
                                            .foregroundStyle(.secondary)
                                        Text("No preview available for this link")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding()
                                    .background(Color.primary.opacity(0.05))
                                    .cornerRadius(10)
                                    .padding(.horizontal)
                                    .padding(.top)
                                }
                            }
                            
                            // Raw Text content
                            Text(item.content)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
    
    var title: String {
        switch item.type {
        case .text: return "Text Content"
        case .image: return "Image Data"
        case .file: return "File Reference"
        }
    }
    
    var dimensionsString: String {
        guard let w = item.width, let h = item.height else { return "Unknown" }
        return "\(Int(w)) × \(Int(h)) pixels"
    }
    
    var fileSizeString: String {
        guard let size = item.fileSize else { return "Unknown" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .font(.system(size: 12))
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.background)
    }
}

// MARK: - Row View

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    @EnvironmentObject var clipboardManager: ClipboardManager
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Thumbnail / Icon
            Group {
                if item.type == .image, let nsImage = clipboardManager.image(for: item) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 24, height: 24)
                        .cornerRadius(3)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? .white : .secondary)
                }
            }
            .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(previewText)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white : .primary)
                Text(item.date, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor)
                .opacity(isSelected ? 1.0 : 0.0)
                .padding(.horizontal, 6)
        )
    }
    
    var previewText: String {
        switch item.type {
        case .text:
            if let title = item.ogTitle, !title.isEmpty {
                return title
            }
            return item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        case .image: return "Image Capture"
        case .file: return URL(fileURLWithPath: item.content).lastPathComponent
        }
    }
    
    var iconName: String {
        switch item.type {
        case .text:
            if item.isURL {
                return "link"
            }
            return "text.alignleft"
        case .image: return "photo"
        case .file: return "paperclip"
        }
    }
}