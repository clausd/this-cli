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

struct Config: Codable {
    let searchDirectories: [String]
    let maxRecentDays: Int
    
    static let `default` = Config(
        searchDirectories: ["~/Documents", "~/Desktop", "~/Downloads"],
        maxRecentDays: 3
    )
}

// MARK: - Main Tool
class ThisTool {
    private let dataDirectory: URL
    private let config: Config
    private let isOutputRedirected: Bool
    
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
        
        // Detect if output is redirected/piped
        isOutputRedirected = isatty(STDOUT_FILENO) == 0
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
    this | grep foo         Pipe clipboard content to grep
    this > file.txt         Save clipboard content to file
    open `this`             Open most relevant file
    this image              Get most recent image
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
        
        // Check clipboard monitor (with shorter timeout for status)
        let monitorRunning = isClipboardMonitorRunning(timeout: 1.0)
        print("Clipboard Monitor: \(monitorRunning ? "✅ Running" : "❌ Not Running")")
        
        // Check data directory
        let dataExists = FileManager.default.fileExists(atPath: dataDirectory.path)
        print("Data Directory: \(dataExists ? "✅ Exists" : "❌ Missing") (\(dataDirectory.path))")
        
        // Check config file
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let configPath = homeDir.appendingPathComponent(".this.config")
        let configExists = FileManager.default.fileExists(atPath: configPath.path)
        print("Config File: \(configExists ? "✅ Exists" : "⚠️  Using defaults") (\(configPath.path))")
        
        // Check clipboard history
        let historyFile = dataDirectory.appendingPathComponent("history.json")
        if let data = try? Data(contentsOf: historyFile),
           let history = try? JSONDecoder().decode([ClipboardEntry].self, from: data) {
            print("Clipboard History: ✅ \(history.count) entries")
        } else {
            print("Clipboard History: ⚠️  No history found")
        }
        
        // Show search directories
        print("\nSearch Directories:")
        for dir in config.searchDirectories {
            let expandedDir = NSString(string: dir).expandingTildeInPath
            let exists = FileManager.default.fileExists(atPath: expandedDir)
            print("  \(exists ? "✅" : "❌") \(dir) (\(expandedDir))")
        }
        
        if !monitorRunning {
            print("\n💡 To start clipboard monitoring:")
            print("   clipboard-helper &")
            print("   # or install as a service with: make install")
        }
    }
    
    // MARK: - Command Handlers
    private func handleDefault() throws {
        // Try clipboard first (without auto-starting monitor to avoid hanging)
        if let entry = getClipboardEntry() {
            output(entry)
        } else if let recentFile = getRecentFiles().first {
            print(recentFile)
        } else {
            // Only try to start monitor if we have no content at all
            if !isClipboardMonitorRunning(timeout: 0.5) {
                fputs("No clipboard history found. Start clipboard monitoring with: clipboard-helper &\n", stderr)
            }
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
        
        // Try clipboard with filter first (without auto-starting to avoid hanging)
        if let entry = getClipboardEntry(matching: filter) {
            output(entry)
        } else {
            // Try recent files with filter
            let recentFiles = getRecentFiles(filter: filter)
            guard let mostRecent = recentFiles.first else {
                // Only suggest starting monitor if this was a clipboard-related query
                if !filter.contains("recent") && !isClipboardMonitorRunning(timeout: 0.5) {
                    fputs("No matching clipboard content found. Start clipboard monitoring with: clipboard-helper &\n", stderr)
                }
                throw ThisError.noMatchingContent(filter)
            }
            print(mostRecent)
        }
    }
    
    // MARK: - Output Logic
    private func output(_ entry: ClipboardEntry) {
        switch entry.type {
        case .text:
            if isOutputRedirected {
                print(entry.content)
            } else {
                // For interactive use, still output content for text
                print(entry.content)
            }
        case .image, .file:
            if let tempPath = entry.tempFilePath {
                print(tempPath)
            } else {
                print(entry.content)
            }
        }
    }
    
    // MARK: - Data Access
    private func getClipboardEntry(matching filter: String? = nil) -> ClipboardEntry? {
        let historyFile = dataDirectory.appendingPathComponent("history.json")
        
        guard let data = try? Data(contentsOf: historyFile) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let history = try? decoder.decode([ClipboardEntry].self, from: data) else {
            return nil
        }
        
        if let filter = filter {
            return history.first { matchesFilter(entry: $0, filter: filter) }
        }
        
        return history.first
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
        
        return results
    }
    
    private func searchWithMdfind(filter: String) -> [String] {
        var results: [String] = []
        
        // Build mdfind query
        let daysAgo = config.maxRecentDays
        let dateThreshold = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: dateThreshold)
        
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
        
        // Search each directory
        for searchDir in config.searchDirectories {
            let expandedDir = NSString(string: searchDir).expandingTildeInPath
            
            guard FileManager.default.fileExists(atPath: expandedDir) else { continue }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            process.arguments = ["-onlyin", expandedDir, query]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        let files = output.components(separatedBy: .newlines)
                            .filter { !$0.isEmpty }
                            .filter { path in
                                // Additional content filtering
                                if !filter.isEmpty && !isFileTypeFilter(filter) {
                                    return path.lowercased().contains(filter)
                                }
                                return true
                            }
                        results.append(contentsOf: files)
                    }
                }
            } catch {
                // Continue on error
            }
        }
        
        return results
    }
    
    private func searchManually(filter: String) -> [String] {
        var results: [String] = []
        let daysAgo = config.maxRecentDays
        let dateThreshold = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        
        // Search each directory manually
        for searchDir in config.searchDirectories {
            let expandedDir = NSString(string: searchDir).expandingTildeInPath
            
            guard FileManager.default.fileExists(atPath: expandedDir) else { continue }
            
            if let enumerator = FileManager.default.enumerator(atPath: expandedDir) {
                while let file = enumerator.nextObject() as? String {
                    let fullPath = "\(expandedDir)/\(file)"
                    
                    // Check if file matches our criteria
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: fullPath),
                       let modDate = attributes[.modificationDate] as? Date,
                       modDate >= dateThreshold {
                        
                        // Apply filters
                        if matchesFileFilter(path: fullPath, filter: filter) {
                            results.append(fullPath)
                        }
                    }
                }
            }
        }
        
        // Sort by modification time (most recent first)
        return results.sorted { path1, path2 in
            let attr1 = try? FileManager.default.attributesOfItem(atPath: path1)
            let attr2 = try? FileManager.default.attributesOfItem(atPath: path2)
            
            let date1 = attr1?[.modificationDate] as? Date ?? Date.distantPast
            let date2 = attr2?[.modificationDate] as? Date ?? Date.distantPast
            
            return date1 > date2
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
    
    // MARK: - Clipboard Monitor Management
    private func ensureClipboardMonitorRunning() {
        // Check if clipboard-helper is already running (with short timeout)
        if isClipboardMonitorRunning(timeout: 0.5) {
            return
        }
        
        // Try to start it (non-blocking)
        startClipboardMonitor()
        
        // Give it a brief moment to start
        usleep(100_000) // 0.1 seconds
        
        // Don't wait long to verify - just inform user
        fputs("Started clipboard monitor in background.\n", stderr)
    }
    
    private func isClipboardMonitorRunning(timeout: TimeInterval = 5.0) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "clipboard-helper"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            
            // Wait with timeout
            let group = DispatchGroup()
            group.enter()
            
            var processFinished = false
            DispatchQueue.global().async {
                process.waitUntilExit()
                processFinished = true
                group.leave()
            }
            
            let result = group.wait(timeout: .now() + timeout)
            
            if result == .timedOut {
                process.terminate()
                return false
            }
            
            if processFinished {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                return process.terminationStatus == 0 && !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            
            return false
        } catch {
            return false
        }
    }
    
    private func startClipboardMonitor() {
        // Try to find clipboard-helper in common locations
        let possiblePaths = [
            "/usr/local/bin/clipboard-helper",
            "./build/clipboard-helper",
            "clipboard-helper" // In PATH
        ]
        
        for path in possiblePaths {
            if startClipboardMonitorAt(path: path) {
                return
            }
        }
    }
    
    private func startClipboardMonitorAt(path: String) -> Bool {
        let process = Process()
        
        if path.starts(with: "/") || path.starts(with: "./") {
            // Absolute or relative path
            guard FileManager.default.fileExists(atPath: path) else { return false }
            process.executableURL = URL(fileURLWithPath: path)
        } else {
            // Command in PATH
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [path]
        }
        
        // Run in background
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        do {
            try process.run()
            return true
        } catch {
            return false
        }
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
