import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var clipboardMonitor: ClipboardMonitor!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "📋"
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "This - Clipboard Monitor", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Show Recent Files", action: #selector(showRecentFiles), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        
        // Start monitoring
        clipboardMonitor = ClipboardMonitor()
        
        // Create data directory if it doesn't exist
        let dataDir = getDataDirectory()
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    }
    
    @objc func showRecentFiles() {
        let workspace = NSWorkspace.shared
        let dataDir = getDataDirectory()
        workspace.open(dataDir)
    }
    
    @objc func clearHistory() {
        ClipboardMonitor.clearHistory()
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
    
    func getDataDirectory() -> URL {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent(".this")
    }
}

struct ClipboardEntry: Codable {
    let timestamp: Date
    let content: String
    let type: ClipboardType
    let tempFilePath: String?
    
    enum ClipboardType: String, Codable {
        case text
        case image
        case file
    }
}

class ClipboardMonitor {
    private var changeCount: Int
    private let pasteboard = NSPasteboard.general
    private let dataDirectory: URL
    private let maxHistoryItems = 100
    
    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        dataDirectory = homeDir.appendingPathComponent(".this")
        
        changeCount = pasteboard.changeCount
        
        // Create data directory
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        
        startMonitoring()
        print("Clipboard monitoring started. Data stored in: \(dataDirectory.path)")
    }
    
    func startMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            if self.pasteboard.changeCount != self.changeCount {
                self.changeCount = self.pasteboard.changeCount
                self.handleClipboardChange()
            }
        }
    }
    
    private func handleClipboardChange() {
        let timestamp = Date()
        var entry: ClipboardEntry?
        
        // Check for image first
        if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            let tempPath = saveTempFile(data: imageData, prefix: "image", extension: getImageExtension(for: imageData))
            entry = ClipboardEntry(
                timestamp: timestamp,
                content: "Image (\(imageData.count) bytes)",
                type: .image,
                tempFilePath: tempPath
            )
        }
        // Check for file URLs
        else if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !fileURLs.isEmpty {
            let filePaths = fileURLs.map { $0.path }.joined(separator: "\n")
            entry = ClipboardEntry(
                timestamp: timestamp,
                content: filePaths,
                type: .file,
                tempFilePath: nil
            )
        }
        // Default to text
        else if let text = pasteboard.string(forType: .string) {
            let tempPath = saveTempFile(text: text, prefix: "text", extension: "txt")
            entry = ClipboardEntry(
                timestamp: timestamp,
                content: text,
                type: .text,
                tempFilePath: tempPath
            )
        }
        
        if let entry = entry {
            saveEntry(entry)
            print("Clipboard changed at \(DateFormatter.localizedString(from: timestamp, dateStyle: .none, timeStyle: .medium))")
            print("Type: \(entry.type.rawValue), Content: \(String(entry.content.prefix(50)))...")
        }
    }
    
    private func getImageExtension(for data: Data) -> String {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if data.starts(with: [0x49, 0x49, 0x2A, 0x00]) || data.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return "tiff" }
        return "png" // default
    }
    
    private func saveTempFile(data: Data, prefix: String, extension: String) -> String {
        let filename = "\(prefix)_\(Int(Date().timeIntervalSince1970)).\(`extension`)"
        let tempPath = dataDirectory.appendingPathComponent(filename)
        
        do {
            try data.write(to: tempPath)
            return tempPath.path
        } catch {
            print("Error saving temp file: \(error)")
            return ""
        }
    }
    
    private func saveTempFile(text: String, prefix: String, extension: String) -> String {
        let filename = "\(prefix)_\(Int(Date().timeIntervalSince1970)).\(`extension`)"
        let tempPath = dataDirectory.appendingPathComponent(filename)
        
        do {
            try text.write(to: tempPath, atomically: true, encoding: .utf8)
            return tempPath.path
        } catch {
            print("Error saving temp file: \(error)")
            return ""
        }
    }
    
    private func saveEntry(_ entry: ClipboardEntry) {
        let historyFile = dataDirectory.appendingPathComponent("history.json")
        
        var history: [ClipboardEntry] = []
        
        // Load existing history
        if let data = try? Data(contentsOf: historyFile),
           let existingHistory = try? JSONDecoder().decode([ClipboardEntry].self, from: data) {
            history = existingHistory
        }
        
        // Add new entry at the beginning
        history.insert(entry, at: 0)
        
        // Keep only recent items
        if history.count > maxHistoryItems {
            // Clean up old temp files
            for oldEntry in history[maxHistoryItems...] {
                if let tempPath = oldEntry.tempFilePath {
                    try? FileManager.default.removeItem(atPath: tempPath)
                }
            }
            history = Array(history.prefix(maxHistoryItems))
        }
        
        // Save updated history with consistent date format
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(history)
            try data.write(to: historyFile)
        } catch {
            print("Error saving history: \(error)")
        }
    }
    
    static func clearHistory() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let dataDirectory = homeDir.appendingPathComponent(".this")
        
        // Remove all files in the data directory
        if let contents = try? FileManager.default.contentsOfDirectory(at: dataDirectory, includingPropertiesForKeys: nil) {
            for file in contents {
                try? FileManager.default.removeItem(at: file)
            }
        }
        
        print("History cleared")
    }
}

// Main application entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Hide dock icon (comment out if you want it to appear in dock)
app.setActivationPolicy(.accessory)

app.run()
