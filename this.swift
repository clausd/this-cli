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
    
    // MARK: - Command Handlers
    private func handleDefault() throws {
        // Try clipboard first, then recent files
        if let entry = getClipboardEntry() {
            output(entry)
        } else if let recentFile = getRecentFiles().first {
            print(recentFile)
        } else {
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
        
        // Try clipboard with filter first
        if let entry = getClipboardEntry(matching: filter) {
            output(entry)
        } else {
            // Try recent files with filter
            let recentFiles = getRecentFiles(filter: filter)
            guard let mostRecent = recentFiles.first else {
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
