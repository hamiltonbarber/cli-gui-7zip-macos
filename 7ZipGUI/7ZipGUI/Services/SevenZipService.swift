import Foundation

enum SevenZipError: Error, LocalizedError {
    case passwordRequired
    case other(String)

    var errorDescription: String? {
        switch self {
        case .passwordRequired:
            return "Archive is password-protected."
        case .other(let message):
            return message
        }
    }
}

class SevenZipService {
    static let shared = SevenZipService()
    
    private let sevenZipPath: String
    
    private init() {
        sevenZipPath = Self.find7ZipExecutable()
    }
    
    private static func find7ZipExecutable() -> String {
        // First try bundled 7-Zip (included with app) - this is the primary method
        if let bundledPath = Bundle.main.path(forResource: "7zz", ofType: nil) {
            if FileManager.default.fileExists(atPath: bundledPath) {
                return bundledPath
            }
        }
        
        // Try relative to the current app bundle's Resources directory
        if let bundlePath = Bundle.main.resourcePath {
            let bundled7zz = (bundlePath as NSString).appendingPathComponent("7zz")
            if FileManager.default.fileExists(atPath: bundled7zz) {
                return bundled7zz
            }
        }
        
        // Try adjacent to the main bundle (for development/debugging)
        let bundleURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("7zz").path
        if FileManager.default.fileExists(atPath: bundleURL) {
            return bundleURL
        }
        
        // Fallback to standard installation paths if bundled version missing
        let standardPaths = [
            "/usr/local/bin/7zz",     // Homebrew Intel
            "/opt/homebrew/bin/7zz",  // Homebrew Apple Silicon
            "/usr/local/bin/7z",      // Alternative name Intel
            "/opt/homebrew/bin/7z"    // Alternative name Apple Silicon
        ]
        
        for path in standardPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // Final fallback to PATH
        return "7zz"
    }
    
    func isAvailable() -> Bool {
        guard FileManager.default.fileExists(atPath: sevenZipPath) else {
            return false
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sevenZipPath)
        process.arguments = []
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    func getInstallationStatus() -> (isInstalled: Bool, path: String, message: String) {
        if FileManager.default.fileExists(atPath: sevenZipPath) {
            return (true, sevenZipPath, "7-Zip found at: \(sevenZipPath)")
        } else {
            let message = """
            7-Zip (7zz) executable not found.
            
            Installation options:
            
            1. Homebrew (recommended):
               brew install p7zip
            
            2. Direct download:
               • Download from: https://www.7-zip.org/download.html
               • Extract and place 7zz in a PATH directory
            
            3. Bundle with app:
               • Place 7zz executable in app bundle Resources
            
            The app searches these locations:
            • Bundled: App bundle Resources/7zz
            • Homebrew Intel: /usr/local/bin/7zz
            • Homebrew ARM: /opt/homebrew/bin/7zz
            • System PATH: 7zz command
            
            Current target: \(sevenZipPath)
            """
            return (false, sevenZipPath, message)
        }
    }
    
    func createArchive(
        files: [String],
        outputPath: String,
        compressionLevel: Int = 5,
        password: String? = nil,
        splitSize: String? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Determine format from output path extension
                let format = (outputPath as NSString).pathExtension.lowercased()
                
                var arguments = ["a"]
                
                // Compression level handling based on format
                // TAR doesn't support compression (it's just an archiver)
                // ZIP and 7z support compression levels
                if format != "tar" {
                    arguments.append("-mx\(compressionLevel)")
                }
                
                if let splitSize = splitSize {
                    arguments.append("-v\(splitSize)")
                }
                
                // Password handling based on format
                if let password = password, !password.isEmpty {
                    // TAR format doesn't support encryption - the password will be ignored
                    // ZIP supports password but not header encryption
                    // 7z supports both password and header encryption
                    if format == "tar" {
                        // TAR doesn't support encryption - this will create an unencrypted archive
                        // The caller should warn the user about this limitation
                    } else {
                        arguments.append("-p\(password)")
                        // Header encryption only supported for 7z format
                        if format == "7z" {
                            arguments.append("-mhe=on")
                        }
                    }
                }
                
                // Exclude macOS metadata files
                arguments.append("-xr!.DS_Store")      // Finder folder metadata
                arguments.append("-xr!._*")            // AppleDouble resource forks
                arguments.append("-xr!.AppleDouble")   // AppleDouble directories
                arguments.append("-xr!.Spotlight-V100") // Spotlight index
                arguments.append("-xr!.Trashes")       // Trash folder
                arguments.append("-xr!.fseventsd")     // File system events
                arguments.append("-xr!Thumbs.db")      // Windows thumbnail cache
                
                arguments.append(outputPath)
                arguments.append(contentsOf: files)
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.sevenZipPath)
                process.arguments = arguments
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                
                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        completion(.success(()))
                    } else {
                        let output = String(data: data, encoding: .utf8) ?? ""
                        let error = NSError(domain: "SevenZipError", code: Int(process.terminationStatus), userInfo: [
                            NSLocalizedDescriptionKey: "Archive creation failed: \(output)"
                        ])
                        completion(.failure(error))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    func extractArchive(
        archivePath: String,
        destinationPath: String,
        selectedFiles: [String]? = nil,
        password: String? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var arguments = ["x", archivePath, "-o\(destinationPath)", "-y"]
                
                if let password = password, !password.isEmpty {
                    arguments.append("-p\(password)")
                }
                
                if let selectedFiles = selectedFiles, !selectedFiles.isEmpty {
                    arguments.append(contentsOf: selectedFiles)
                }
                
                // Subprocess handling for GUI - no interactive prompts allowed
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.sevenZipPath)
                process.arguments = arguments
                
                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = outputPipe
                // Important: Close stdin to prevent 7zz from waiting for input
                process.standardInput = nil
                
                try process.run()
                process.waitUntilExit()
                
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        completion(.success(()))
                    } else if output.contains("Enter password") || output.contains("Wrong password") || process.terminationStatus == 255 {
                        completion(.failure(SevenZipError.passwordRequired))
                    } else {
                        let error = NSError(domain: "SevenZipError", code: Int(process.terminationStatus), userInfo: [
                            NSLocalizedDescriptionKey: "Extraction failed: \(output)"
                        ])
                        completion(.failure(error))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    func listArchiveContents(
        archivePath: String,
        password: String? = nil,
        completion: @escaping (Result<[ArchiveFileInfo], Error>) -> Void
    ) {
        // Run on background queue to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var arguments = ["l", "-slt", archivePath]
                
                if let password = password, !password.isEmpty {
                    arguments.append("-p\(password)")
                }
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.sevenZipPath)
                process.arguments = arguments
                process.standardInput = nil // Close stdin to prevent hanging
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                
                let output = String(data: data, encoding: .utf8) ?? ""
                
                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        let files = self.parseArchiveContents(output, archivePath: archivePath)
                        completion(.success(files))
                    } else {
                        if output.contains("Enter password") {
                            completion(.failure(SevenZipError.passwordRequired))
                        } else {
                            let errorMessage = "Failed to list archive contents. Exit code: \(process.terminationStatus). Output: \(output)"
                            completion(.failure(SevenZipError.other(errorMessage)))
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Archive Content Parsing
    
    private func parseArchiveContents(_ output: String, archivePath: String) -> [ArchiveFileInfo] {
        // Split the output into blocks, where each block represents a file and its properties.
        // Each block is separated by a blank line.
        let blocks = output.components(separatedBy: "\n\n")
        var files: [ArchiveFileInfo] = []

        for block in blocks {
            let lines = block.components(separatedBy: .newlines)
            var fileData: [String: String] = [:]

            for line in lines {
                if let (key, value) = parseLine(line) {
                    fileData[key] = value
                }
            }

            if !fileData.isEmpty {
                let fileInfo = createArchiveFileInfo(from: fileData)
                // Filter out the archive file itself and empty entries
                if !fileInfo.path.isEmpty && !fileInfo.path.hasSuffix(".7z") && !fileInfo.path.contains(URL(fileURLWithPath: archivePath).lastPathComponent) {
                    files.append(fileInfo)
                }
            }
        }

        return files
    }
    // Helper function to parse a single line of the 7zz output.
    private func parseLine(_ line: String) -> (String, String)? {
        let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2 {
            return (parts[0].lowercased(), parts[1])
        }
        return nil
    }
    
    private func createArchiveFileInfo(from data: [String: String]) -> ArchiveFileInfo {
        let path = data["path"] ?? ""
        let size = Int64(data["size"] ?? "0") ?? 0
        let isDirectory = data["folder"] == "+"
        
        var modificationDate: Date?
        if let modifiedString = data["modified"] {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            modificationDate = formatter.date(from: modifiedString)
        }
        
        return ArchiveFileInfo(
            path: path,
            size: size,
            isDirectory: isDirectory,
            modificationDate: modificationDate
        )
    }
}
