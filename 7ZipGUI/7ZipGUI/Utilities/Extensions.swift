import Foundation

extension DateFormatter {
    static let archiveDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    static let fileDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

extension String {
    func cleanedPath() -> String {
        // Handle macOS drag-and-drop path escaping
        return self
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .replacingOccurrences(of: "\\ ", with: " ")
            .replacingOccurrences(of: "\\(", with: "(")
            .replacingOccurrences(of: "\\)", with: ")")
            .replacingOccurrences(of: "\\&", with: "&")
    }
    
    /// Check if path is a protected system directory
    func isSystemProtectedPath() -> Bool {
        let absolutePath = NSString(string: self).expandingTildeInPath
        return absolutePath.hasPrefix("/System") || 
               absolutePath.hasPrefix("/usr/bin") || 
               absolutePath.hasPrefix("/private")
    }
}

extension Array where Element == String {
    func validPaths() -> [String] {
        return self.compactMap { path in
            let cleanedPath = path.cleanedPath()
            guard !cleanedPath.isEmpty && !cleanedPath.isSystemProtectedPath() else { return nil }
            return FileManager.default.fileExists(atPath: cleanedPath) ? cleanedPath : nil
        }
    }
}
