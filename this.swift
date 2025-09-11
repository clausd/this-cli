#!/usr/bin/env swift

import Foundation

// MARK: - Data Models
struct ClipboardEntry: Codable {
    let timestamp: Date
    let content: String
    let type: ClipboardType
    let tempFilePath: String?
    
    enum ClipboardType: String, Codable {
        case text, image, file
    }
}

// Unified item type for comparing across sources
enum RecentItem {
    case clipboardEntry(ClipboardEntry)
    case filePath(String, Date)
    
    var timestamp: Date {
        switch self {
        case .clipboardEntry(let entry):
            return entry.timestamp
        case .filePath(_, let date):
            return date
        }
    }
}

struct Config: Codable {
    let searchDirectories: [String]
    let maxRecentDays: Int
    
    static let `default` = Config(
        searchDirectories: ["~/Documents", "~/Desktop", "~/Downloads"],
        maxRecentDays: 3
    )
    
    // 10 minute cutoff for "recent" files
    var maxRecentMinutes: Int { return 10 }
}

// MARK: - Main Tool
class ThisTool {
    private let dataDirectory: URL
    private let config: Config
    
    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        dataDirectory = homeDir.appendingPathComponent(".this")
        
        // Load config
        let configPath = homeDir.appendingPathComponent(".this.config")
        if let configData = try? Data(contentsOf: configPath),
           let loadedConfig = try? JSONDecoder().decode(Config.self, from: configData) {
            config = loadedConfig
        } else {
            config = Config.default
        }
    }
    
    func run() {
        let args = Array(CommandLine.arguments.dropFirst())
        
        do {
            if args.isEmpty {
                try handleDefault()
            } else if args[0] == "--help" || args[0] == "-h" {
                showHelp()
                exit(0)
            } else if args[0] == "status" || args[0] == "-s" {
                showStatus()
                exit(0)
            } else if args[0] == "recent" {
                try handleRecent(filters: Array(args.dropFirst()))
            } else {
                try handleFiltered(filters: args)
            }
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    
    private func showHelp() {
        print("""
this - Context-aware clipboard and file tool

USAGE:
    this                    Get most recent clipboard content
    this [filter]           Get clipboard content matching filter
    this recent [filter]    Get most recent file matching filter
    this status, -s         Show clipboard monitor status
    this --help, -h         Show this help message

EXAMPLES:
    open `this`             Open most relevant file
    cp `this` backup/       Copy most relevant file
    cat `this`              View content of most relevant file
    this image              Get most recent image file
    this recent txt         Get most recent .txt file
    this -s                 Quick status check

FILTERS:
    image, img              Images (png, jpg, gif)
    text, txt               Text files or clipboard text
    png, jpg, pdf           Specific file types
    [keyword]               Content containing keyword

CONFIG:
    ~/.this.config          JSON configuration file
    ~/.this/                Data directory

For detailed documentation: man this
""")
    }
    
    private func showStatus() {
        print("This Tool Status")
        print("================")
        
        // Check data directory (fast, no network/process calls)
        let dataExists = FileManager.default.fileExists(atPath: dataDirectory.path)
        print("Data Directory: \(dataExists ? "✅ Exists" : "❌ Missing") (\(dataDirectory.path))")
        
        // Check config file (fast, no network/process calls)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let configPath = homeDir.appendingPathComponent(".this.config")
        let configExists = FileManager.default.fileExists(atPath: configPath.path)
        print("Config File: \(configExists ? "✅ Exists" : "⚠️  Using defaults") (\(configPath.path))")
        
        // Check clipboard history (fast, just file reading)
        let historyFile = dataDirectory.appendingPathComponent("history.json")
        if let data = try? Data(contentsOf: historyFile) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let history = try? decoder.decode([ClipboardEntry].self, from: data) {
                print("Clipboard History: ✅ \(history.count) entries")
            } else {
                print("Clipboard History: ⚠️  Invalid format")
            }
        } else {
            print("Clipboard History: ⚠️  No history found")
        }
        
        // Show search directories (fast, just file system checks)
        print("\nSearch Directories:")
        for dir in config.searchDirectories {
            let expandedDir = NSString(string: dir).expandingTildeInPath
            let exists = FileManager.default.fileExists(atPath: expandedDir)
            print("  \(exists ? "✅" : "❌") \(dir) (\(expandedDir))")
        }
        
        print("\n💡 To start clipboard monitoring:")
        print("   clipboard-helper &")
        print("   # or install as a service with: make install")
        print("\n💡 To check if clipboard monitor is running:")
        print("   pgrep -f clipboard-helper")
    }
    
    // MARK: - Command Handlers
    private func handleDefault() throws {
        // Get the most recent item across all sources
        if let mostRecent = getMostRecentItem() {
            outputItem(mostRecent)
        } else {
            fputs("No clipboard history or recent files found. Start clipboard monitoring with: clipboard-helper &\n", stderr)
            throw ThisError.noContentFound
        }
    }
    
    private func handleRecent(filters: [String]) throws {
        let filter = filters.joined(separator: " ")
        let recentFiles = getRecentFiles(filter: filter)
        
        guard let mostRecent = recentFiles.first else {
            throw ThisError.noRecentFiles
        }
        
        print(mostRecent)
    }
    
    private func handleFiltered(filters: [String]) throws {
        let filter = filters.joined(separator: " ").lowercased()
        
        // Get the most recent item across all sources with filter
        if let mostRecent = getMostRecentItem(matching: filter) {
            outputItem(mostRecent)
        } else {
            fputs("No content found matching filter: \(filter). Start clipboard monitoring with: clipboard-helper &\n", stderr)
            throw ThisError.noMatchingContent(filter)
        }
    }
    
    // MARK: - Output Logic
    private func output(_ entry: ClipboardEntry) {
        // Always output file path when available
        if let tempPath = entry.tempFilePath {
            print(tempPath)
        } else {
            // Fallback to content description for entries without temp files
            print(entry.content)
        }
    }
    
    private func outputItem(_ item: RecentItem) {
        switch item {
        case .clipboardEntry(let entry):
            output(entry)
        case .filePath(let path, _):
            print(path)
        }
    }
    
    // MARK: - Data Access
    private func getMostRecentItem(matching filter: String? = nil) -> RecentItem? {
        var allItems: [RecentItem] = []
        
        // Get clipboard entries
        if let clipboardEntries = getClipboardEntries() {
            for entry in clipboardEntries {
                if let filter = filter {
                    if matchesFilter(entry: entry, filter: filter) {
                        allItems.append(.clipboardEntry(entry))
                    }
                } else {
                    allItems.append(.clipboardEntry(entry))
                }
            }
        }
        
        // Get recent files
        let recentFiles = getRecentFiles(filter: filter ?? "")
        for filePath in recentFiles {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: filePath),
               let modDate = attributes[.modificationDate] as? Date {
                allItems.append(.filePath(filePath, modDate))
            }
        }
        
        // Sort by timestamp (most recent first) and return the first
        return allItems.sorted { $0.timestamp > $1.timestamp }.first
    }
    
    private func getClipboardEntry(matching filter: String? = nil) -> ClipboardEntry? {
        return getClipboardEntries()?.first { entry in
            if let filter = filter {
                return matchesFilter(entry: entry, filter: filter)
            }
            return true
        }
    }
    
    private func getClipboardEntries() -> [ClipboardEntry]? {
        let historyFile = dataDirectory.appendingPathComponent("history.json")
        
        guard let data = try? Data(contentsOf: historyFile) else {
            return nil
        }
        
        // Try multiple date decoding strategies
        let decoder = JSONDecoder()
        
        // First try ISO8601
        decoder.dateDecodingStrategy = .iso8601
        if let history = try? decoder.decode([ClipboardEntry].self, from: data) {
            return history
        }
        
        // Try default date format
        decoder.dateDecodingStrategy = .deferredToDate
        if let history = try? decoder.decode([ClipboardEntry].self, from: data) {
            return history
        }
        
        // Try custom date formatter
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        decoder.dateDecodingStrategy = .formatted(formatter)
        
        if let history = try? decoder.decode([ClipboardEntry].self, from: data) {
            return history
        }
        
        return nil
    }
    
    private func getRecentFiles(filter: String = "") -> [String] {
        let filter = filter.lowercased()
        var results: [String] = []
        
        // Try mdfind first, then fallback to manual search
        results = searchWithMdfind(filter: filter)
        
        // If mdfind didn't work (common in test environments), use manual search
        if results.isEmpty {
            results = searchManually(filter: filter)
        }
        
        // Sort results globally by modification time (most recent first)
        return results.sorted { path1, path2 in
            // Get modification dates
            let attr1 = try? FileManager.default.attributesOfItem(atPath: path1)
            let attr2 = try? FileManager.default.attributesOfItem(atPath: path2)
            let mod1 = attr1?[.modificationDate] as? Date ?? Date.distantPast
            let mod2 = attr2?[.modificationDate] as? Date ?? Date.distantPast
            
            return mod1 > mod2
        }
    }
    
    private func searchWithMdfind(filter: String) -> [String] {
        var results: [String] = []
        
        // Use 10-minute cutoff for truly recent files
        let minutesAgo = config.maxRecentMinutes
        let dateThreshold = Calendar.current.date(byAdding: .minute, value: -minutesAgo, to: Date()) ?? Date()
        
        // Use precise timestamp format for mdfind
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = formatter.string(from: dateThreshold)
        
        // Query for recently modified files only (more reliable than LastUsedDate)
        var query = "kMDItemFSContentChangeDate >= '\(dateString)'"
        
        // Add file type filters
        if filter.contains("png") {
            query += " && kMDItemDisplayName == '*.png'c"
        } else if filter.contains("jpg") || filter.contains("jpeg") {
            query += " && (kMDItemDisplayName == '*.jpg'c || kMDItemDisplayName == '*.jpeg'c)"
        } else if filter.contains("txt") || filter.contains("text") {
            query += " && kMDItemDisplayName == '*.txt'c"
        } else if filter.contains("pdf") {
            query += " && kMDItemDisplayName == '*.pdf'c"
        } else if filter.contains("image") || filter.contains("img") {
            query += " && (kMDItemDisplayName == '*.png'c || kMDItemDisplayName == '*.jpg'c || kMDItemDisplayName == '*.jpeg'c || kMDItemDisplayName == '*.gif'c)"
        }
        
        // Search ALL directories in one mdfind call for better performance and global sorting
        let expandedDirs = config.searchDirectories
            .map { NSString(string: $0).expandingTildeInPath }
            .filter { FileManager.default.fileExists(atPath: $0) }
        
        guard !expandedDirs.isEmpty else { return [] }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        
        // Build arguments with multiple -onlyin flags
        var arguments = [String]()
        for dir in expandedDirs {
            arguments.append("-onlyin")
            arguments.append(dir)
        }
        arguments.append(query)
        
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            
            // Add timeout to prevent hanging
            let group = DispatchGroup()
            group.enter()
            
            var processFinished = false
            DispatchQueue.global().async {
                process.waitUntilExit()
                processFinished = true
                group.leave()
            }
            
            let result = group.wait(timeout: .now() + 2.0) // 2 second timeout for all dirs
            
            if result == .timedOut {
                process.terminate()
                return []
            }
            
            if processFinished && process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    results = output.components(separatedBy: .newlines)
                        .filter { !$0.isEmpty }
                        .filter { path in
                            // Additional content filtering
                            if !filter.isEmpty && !isFileTypeFilter(filter) {
                                return path.lowercased().contains(filter)
                            }
                            return true
                        }
                }
            }
        } catch {
            // Continue on error
        }
        
        return results
    }
    
    private func searchManually(filter: String) -> [String] {
        var results: [String] = []
        let minutesAgo = config.maxRecentMinutes
        let dateThreshold = Calendar.current.date(byAdding: .minute, value: -minutesAgo, to: Date()) ?? Date()
        
        // Search each directory manually and collect ALL results first
        for searchDir in config.searchDirectories {
            let expandedDir = NSString(string: searchDir).expandingTildeInPath
            
            guard FileManager.default.fileExists(atPath: expandedDir) else { continue }
            
            if let enumerator = FileManager.default.enumerator(atPath: expandedDir) {
                while let file = enumerator.nextObject() as? String {
                    let fullPath = "\(expandedDir)/\(file)"
                    
                    // Check if file matches our criteria - use stat to get real access time
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: fullPath) {
                        let modDate = attributes[.modificationDate] as? Date ?? Date.distantPast
                        
                        // File is recent if modified within 10-minute threshold
                        let isRecent = modDate >= dateThreshold
                        
                        if isRecent && matchesFileFilter(path: fullPath, filter: filter) {
                            results.append(fullPath)
                        }
                    }
                }
            }
        }
        
        // Sort ALL results globally by modification time (most recent first)
        return results.sorted { path1, path2 in
            // Get modification dates
            let attr1 = try? FileManager.default.attributesOfItem(atPath: path1)
            let attr2 = try? FileManager.default.attributesOfItem(atPath: path2)
            let mod1 = attr1?[.modificationDate] as? Date ?? Date.distantPast
            let mod2 = attr2?[.modificationDate] as? Date ?? Date.distantPast
            
            return mod1 > mod2
        }
    }
    
    private func matchesFileFilter(path: String, filter: String) -> Bool {
        let pathLower = path.lowercased()
        let filter = filter.lowercased()
        
        if filter.isEmpty { return true }
        
        // Extension-based filtering
        if filter.contains("png") && pathLower.hasSuffix(".png") { return true }
        if filter.contains("jpg") && (pathLower.hasSuffix(".jpg") || pathLower.hasSuffix(".jpeg")) { return true }
        if filter.contains("jpeg") && pathLower.hasSuffix(".jpeg") { return true }
        if filter.contains("txt") && pathLower.hasSuffix(".txt") { return true }
        if filter.contains("text") && pathLower.hasSuffix(".txt") { return true }
        if filter.contains("pdf") && pathLower.hasSuffix(".pdf") { return true }
        if filter.contains("image") || filter.contains("img") {
            return pathLower.hasSuffix(".png") || pathLower.hasSuffix(".jpg") || 
                   pathLower.hasSuffix(".jpeg") || pathLower.hasSuffix(".gif")
        }
        
        // Content-based filtering (filename contains filter)
        if !isFileTypeFilter(filter) {
            return pathLower.contains(filter)
        }
        
        return false
    }
    
    
    // MARK: - Helper Functions
    private func matchesFilter(entry: ClipboardEntry, filter: String) -> Bool {
        let filter = filter.lowercased()
        
        // Type-based filtering
        if filter.contains("image") || filter.contains("img") {
            return entry.type == .image
        }
        if filter.contains("text") || filter.contains("txt") {
            return entry.type == .text
        }
        if filter.contains("file") {
            return entry.type == .file
        }
        
        // Extension-based filtering
        if let tempPath = entry.tempFilePath {
            let pathLower = tempPath.lowercased()
            if filter.contains("png") && pathLower.contains(".png") { return true }
            if filter.contains("jpg") && (pathLower.contains(".jpg") || pathLower.contains(".jpeg")) { return true }
            if filter.contains("txt") && pathLower.contains(".txt") { return true }
        }
        
        // Content-based filtering
        return entry.content.lowercased().contains(filter)
    }
    
    private func isFileTypeFilter(_ filter: String) -> Bool {
        let fileTypes = ["png", "jpg", "jpeg", "txt", "text", "pdf", "image", "img"]
        return fileTypes.contains { filter.contains($0) }
    }
}

// MARK: - Error Types
enum ThisError: Error, LocalizedError {
    case noContentFound
    case noRecentFiles
    case noMatchingContent(String)
    
    var errorDescription: String? {
        switch self {
        case .noContentFound:
            return "No clipboard history or recent files found"
        case .noRecentFiles:
            return "No recent files found"
        case .noMatchingContent(let filter):
            return "No content found matching filter: \(filter)"
        }
    }
}

// MARK: - Main Execution
let tool = ThisTool()
tool.run()
