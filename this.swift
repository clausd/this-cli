#!/usr/bin/env swift

import Foundation

var standardError = FileHandle.standardError

extension FileHandle: TextOutputStream {
    public func write(_ string: String) {
        let data = Data(string.utf8)
        self.write(data)
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

struct Config: Codable {
    let searchDirectories: [String]
    let maxRecentDays: Int
    
    static let `default` = Config(
        searchDirectories: ["~/Documents", "~/Desktop", "~/Downloads"],
        maxRecentDays: 3
    )
}

class ThisTool {
    private let dataDirectory: URL
    private let config: Config
    
    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        dataDirectory = homeDir.appendingPathComponent(".this")
        
        // Load config or use default
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
        
        // Detect if stdout is a pipe or redirected
        let isOutputRedirected = isatty(STDOUT_FILENO) == 0
        
        if args.isEmpty {
            handleDefault(outputRedirected: isOutputRedirected)
        } else if args[0] == "recent" {
            handleRecent(args: Array(args.dropFirst()), outputRedirected: isOutputRedirected)
        } else {
            handleFiltered(args: args, outputRedirected: isOutputRedirected)
        }
    }
    
    private func handleDefault(outputRedirected: Bool) {
        if let entry = getMostRecentClipboardEntry() {
            outputEntry(entry, outputRedirected: outputRedirected)
        } else {
            fputs("No clipboard history found\n", stderr)
            exit(1)
        }
    }
    
    private func handleRecent(args: [String], outputRedirected: Bool) {
        let recentFiles = getRecentFiles(filter: args.joined(separator: " "))
        
        if !recentFiles.isEmpty {
            let mostRecent = recentFiles[0]
            if outputRedirected {
                print(mostRecent)
            } else {
                print(mostRecent)
            }
        } else if let entry = getMostRecentClipboardEntry() {
            outputEntry(entry, outputRedirected: outputRedirected)
        } else {
            fputs("No recent files or clipboard history found\n", stderr)
            exit(1)
        }
    }
    
    private func handleFiltered(args: [String], outputRedirected: Bool) {
        let filterText = args.joined(separator: " ").lowercased()
        
        // Check if this is a recent filter
        if filterText.hasPrefix("recent ") {
            let actualFilter = String(filterText.dropFirst(7))
            let recentFiles = getRecentFiles(filter: actualFilter)
            
            if !recentFiles.isEmpty {
                let mostRecent = recentFiles[0]
                if outputRedirected {
                    print(mostRecent)
                } else {
                    print(mostRecent)
                }
                return
            }
        }
        
        // Filter clipboard entries
        if let entry = getMostRecentClipboardEntry(matching: filterText) {
            outputEntry(entry, outputRedirected: outputRedirected)
        } else {
            fputs("No matching clipboard entry found for filter: \(filterText)\n", stderr)
            exit(1)
        }
    }
    
    private func outputEntry(_ entry: ClipboardEntry, outputRedirected: Bool) {
        if outputRedirected || entry.type == .text {
            // Output content directly for pipes/redirects or text
            if entry.type == .text {
                print(entry.content)
            } else if let tempPath = entry.tempFilePath {
                print(tempPath)
            } else {
                print(entry.content)
            }
        } else {
            // Output file path for interactive use with non-text
            if let tempPath = entry.tempFilePath {
                print(tempPath)
            } else {
                print(entry.content)
            }
        }
    }
    
    private func getMostRecentClipboardEntry(matching filter: String? = nil) -> ClipboardEntry? {
        let historyFile = dataDirectory.appendingPathComponent("history.json")
        
        guard let data = try? Data(contentsOf: historyFile),
              let history = try? JSONDecoder().decode([ClipboardEntry].self, from: data) else {
            return nil
        }
        
        if let filter = filter {
            return history.first { entry in
                matchesFilter(entry: entry, filter: filter)
            }
        }
        
        return history.first
    }
    
    private func matchesFilter(entry: ClipboardEntry, filter: String) -> Bool {
        let filter = filter.lowercased()
        
        // Type-based filtering
        if filter.contains("image") || filter.contains("img") || filter.contains("png") || 
           filter.contains("jpg") || filter.contains("jpeg") || filter.contains("gif") {
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
    
    private func getRecentFiles(filter: String = "") -> [String] {
        let filter = filter.lowercased()
        var results: [String] = []
        
        // Calculate date threshold (use modification date since it's more reliable)
        let daysAgo = config.maxRecentDays
        let dateThreshold = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let timestamp = dateThreshold.timeIntervalSince1970
        
        // Build simpler mdfind query using modification date
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
        
        // Search in configured directories
        for searchDir in config.searchDirectories {
            let expandedDir = NSString(string: searchDir).expandingTildeInPath
            
            // Skip if directory doesn't exist
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: expandedDir, isDirectory: &isDir) && isDir.boolValue else {
                continue
            }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            process.arguments = ["-onlyin", expandedDir, query]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe() // Suppress errors
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        let files = output.components(separatedBy: .newlines)
                            .filter { !$0.isEmpty }
                            .filter { path in
                                // Additional content filtering if needed
                                if !filter.isEmpty && !filter.contains("png") && !filter.contains("jpg") && 
                                   !filter.contains("jpeg") && !filter.contains("txt") && !filter.contains("text") &&
                                   !filter.contains("pdf") && !filter.contains("image") && !filter.contains("img") {
                                    return path.lowercased().contains(filter)
                                }
                                return true
                            }
                        results.append(contentsOf: files)
                    }
                }
            } catch {
                // Continue if mdfind fails for this directory
                print("Warning: mdfind failed for \(expandedDir): \(error)", to: &standardError)
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
}

// Main execution
let tool = ThisTool()
tool.run()
