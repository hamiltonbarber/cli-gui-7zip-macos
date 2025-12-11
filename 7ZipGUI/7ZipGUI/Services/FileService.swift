import Foundation
import AppKit

class FileService {
    static let shared = FileService()
    
    private init() {}
    
    // MARK: - File Validation
    
    func validateFilesForArchiving(_ filePaths: [String]) -> [String] {
        var validatedFiles: [String] = []
        
        for filePath in filePaths {
            guard !filePath.isEmpty else { continue }
            
            let cleanedPath = filePath.cleanedPath()
            guard !cleanedPath.isSystemProtectedPath() else { continue }
            
            let absolutePath = NSString(string: cleanedPath).expandingTildeInPath
            
            if FileManager.default.fileExists(atPath: absolutePath) {
                validatedFiles.append(absolutePath)
            }
        }
        
        return validatedFiles
    }
    
    // MARK: - Archive Naming
    
    func generateSmartArchiveName(for sourceFiles: [String]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        
        if sourceFiles.count == 1 {
            let source = sourceFiles[0]
            let baseName = URL(fileURLWithPath: source).lastPathComponent
            
            if isDirectory(source) {
                return "\(baseName).7z"
            } else {
                let nameWithoutExtension = URL(fileURLWithPath: baseName).deletingPathExtension().lastPathComponent
                return "\(nameWithoutExtension)_archive.7z"
            }
        } else {
            // Multiple files - analyze content type
            let fileNames = sourceFiles.map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() }
            
            let baseName: String
            if fileNames.contains(where: { $0.contains("photo") || $0.contains("img") || 
                                         $0.hasSuffix(".jpg") || $0.hasSuffix(".png") || 
                                         $0.hasSuffix(".gif") || $0.hasSuffix(".heic") }) {
                baseName = "Photos"
            } else if fileNames.contains(where: { $0.contains("doc") || 
                                                 $0.hasSuffix(".pdf") || $0.hasSuffix(".txt") || 
                                                 $0.hasSuffix(".docx") || $0.hasSuffix(".pages") }) {
                baseName = "Documents"
            } else if fileNames.contains(where: { $0.contains("video") || $0.contains("movie") || 
                                                 $0.hasSuffix(".mp4") || $0.hasSuffix(".mov") || 
                                                 $0.hasSuffix(".avi") }) {
                baseName = "Videos"
            } else if fileNames.contains(where: { $0.contains("music") || $0.contains("audio") || 
                                                 $0.hasSuffix(".mp3") || $0.hasSuffix(".m4a") || 
                                                 $0.hasSuffix(".wav") }) {
                baseName = "Audio"
            } else if fileNames.contains(where: { $0.contains("project") || $0.contains("src") || 
                                                 $0.contains("code") }) {
                baseName = "Project"
            } else {
                baseName = "Mixed_Files"
            }
            
            return "\(baseName)_\(dateString).7z"
        }
    }
    
    func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
    
    // MARK: - Size Calculation
    
    func calculateTotalSize(for paths: [String]) -> Int64 {
        var totalSize: Int64 = 0
        
        for path in paths {
            if isDirectory(path) {
                totalSize += calculateDirectorySize(path)
            } else {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: path)
                    if let fileSize = attributes[.size] as? Int64 {
                        totalSize += fileSize
                    }
                } catch {
                    continue
                }
            }
        }
        
        return totalSize
    }
    
    private func calculateDirectorySize(_ path: String) -> Int64 {
        var totalSize: Int64 = 0
        
        guard let enumerator = FileManager.default.enumerator(atPath: path) else {
            return 0
        }
        
        for case let fileName as String in enumerator {
            let filePath = (path as NSString).appendingPathComponent(fileName)
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: filePath)
                if let fileSize = attributes[.size] as? Int64 {
                    totalSize += fileSize
                }
            } catch {
                continue
            }
        }
        
        return totalSize
    }
    
    // MARK: - Disk Space Management
    
    func checkDiskSpace(for outputPath: String, estimatedSize: Int64? = nil) -> (hasSpace: Bool, message: String?) {
        do {
            let outputDir = URL(fileURLWithPath: outputPath).deletingLastPathComponent()
            let resourceValues = try outputDir.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            
            guard let availableCapacity = resourceValues.volumeAvailableCapacity else {
                return (true, nil)
            }
            
            if let estimatedSize = estimatedSize {
                let requiredSpace = Int64(Double(estimatedSize) * 1.2) // 20% buffer
                
                if availableCapacity < requiredSpace {
                    let availableGB = Double(availableCapacity) / (1024 * 1024 * 1024)
                    let requiredGB = Double(requiredSpace) / (1024 * 1024 * 1024)
                    return (false, "Insufficient disk space. Required: \(String(format: "%.1f", requiredGB))GB, Available: \(String(format: "%.1f", availableGB))GB")
                }
            }
            
            // General low space warning
            let availableGB = Double(availableCapacity) / (1024 * 1024 * 1024)
            if availableGB < 1.0 {
                return (true, "Low disk space warning: \(String(format: "%.1f", availableGB))GB available")
            }
            
            return (true, nil)
        } catch {
            return (true, nil) // Don't block operation if check fails
        }
    }
    
    func estimateArchiveSize(for paths: [String], compressionLevel: Int) -> Int64 {
        let totalSize = calculateTotalSize(for: paths)
        
        // Estimate compression ratios based on level
        let compressionRatios: [Int: Double] = [
            0: 1.0,    // Store - no compression
            1: 0.7,    // Fast - ~30% compression
            2: 0.65,   
            3: 0.6,    
            4: 0.55,   
            5: 0.5,    // Normal - ~50% compression
            6: 0.45,   
            7: 0.4,    
            8: 0.35,   
            9: 0.3     // Ultra - ~70% compression
        ]
        
        let ratio = compressionRatios[compressionLevel] ?? 0.5
        return Int64(Double(totalSize) * ratio)
    }
    
    // MARK: - System Integration
    
    func openContainingFolder(for path: String) {
        let folderURL: URL
        
        if isDirectory(path) {
            folderURL = URL(fileURLWithPath: path)
        } else {
            folderURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        
        NSWorkspace.shared.open(folderURL)
    }
    
    func selectFileInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Security Validation
    
    /// Validates output path to prevent writing to system directories
    func validateOutputPath(_ outputPath: String) -> (isValid: Bool, message: String?) {
        let cleanedPath = outputPath.cleanedPath()
        guard !cleanedPath.isEmpty else {
            return (false, "Invalid output path")
        }
        
        if cleanedPath.isSystemProtectedPath() {
            return (false, "Cannot create archives in system directories")
        }
        
        return (true, nil)
    }
}
