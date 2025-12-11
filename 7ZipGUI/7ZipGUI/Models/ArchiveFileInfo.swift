import Foundation

struct ArchiveFileInfo {
    let path: String
    let size: Int64
    let isDirectory: Bool
    let modificationDate: Date?
    
    var displaySize: String {
        if isDirectory { return "Folder" }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024) }
        if size < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(size) / (1024 * 1024)) }
        return String(format: "%.1f GB", Double(size) / (1024 * 1024 * 1024))
    }
}
