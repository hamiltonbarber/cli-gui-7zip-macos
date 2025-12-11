import SwiftUI
import Foundation
import Combine

@MainActor
class ArchiveViewModel: ObservableObject {
    // MARK: - Published Properties
    
    // File selection
    @Published var selectedFiles: [String] = []
    @Published var selectedArchive: String = ""
    @Published var selectedArchives: [String] = [] // Multi-archive support
    
    // Archive settings
    @Published var archiveName: String = ""
    @Published var archiveFormat: String = "7z"
    @Published var compressionLevel: Double = 5
    @Published var usePassword: Bool = false
    @Published var password: String = ""
    @Published var confirmPassword: String = ""
    @Published var archiveOutputLocation: String? = nil // Custom output location
    
    // Extraction settings
    @Published var extractionMode: String = "all"
    @Published var extractDestination: String = ""
    @Published var archiveContents: [String] = []
    @Published var multiArchiveExtractionMode: String = "separate" // "separate" or "combined"
    
    // Operation state
    @Published var isOperationRunning: Bool = false
    @Published var currentOperation: String = ""
    @Published var outputText: String = ""
    @Published var errorMessage: String = ""
    
    // Selective extraction
    @Published var selectableFiles: [ArchiveFileInfo] = []
    @Published var selectedFileIndices: Set<Int> = []
    @Published var fileTreeNodes: [FileTreeNode] = []
    @Published var isPasswordPromptVisible = false
    @Published var archivePassword = ""
    
    // Password operation tracking
    private var pendingPasswordOperation: PasswordOperation?
    
    enum PasswordOperation {
        case viewArchive
        case extractArchive
    }
    
    // MARK: - Services
    
    private let sevenZipService = SevenZipService.shared
    private let fileService = FileService.shared
    let userPreferences = UserPreferencesService()
    
    // MARK: - Initialization
    
    init() {
        setupInitialState()
    }
    
    private func setupInitialState() {
        // Set initial extraction destination based on preferences
        let prefs = userPreferences.preferences
        extractDestination = prefs.rememberLastDirectory && !prefs.lastOutputDirectory.isEmpty 
            ? prefs.lastOutputDirectory 
            : prefs.defaultOutputDirectory
        
        // Set initial compression level based on preferences
        applyCompressionPreferences()
    }
    
    private func applyCompressionPreferences() {
        let prefs = userPreferences.preferences
        
        switch prefs.compressionPreset {
        case "fast":
            compressionLevel = 1
        case "balanced":
            compressionLevel = 5
        case "maximum":
            compressionLevel = 9
        case "custom":
            compressionLevel = Double(prefs.customCompressionLevel)
        default:
            compressionLevel = 5 // fallback to balanced
        }
    }
    
    // MARK: - File Management
    
    func addFile(_ path: String) {
        let cleanedPath = path.cleanedPath()
        
        if !selectedFiles.contains(cleanedPath) {
            selectedFiles.append(cleanedPath)
            updateArchiveName()
            clearError()
        }
    }
    
    func addFiles(_ paths: [String]) {
        let validPaths = paths.validPaths()
        let validatedPaths = fileService.validateFilesForArchiving(validPaths)
        
        for path in validatedPaths {
            if !selectedFiles.contains(path) {
                selectedFiles.append(path)
            }
        }
        
        updateArchiveName()
        
        if validatedPaths.isEmpty && !validPaths.isEmpty {
            setError("No valid files found after security validation")
        } else {
            clearError()
        }
    }
    
    func removeFile(_ path: String) {
        selectedFiles.removeAll { $0 == path }
        updateArchiveName()
    }
    
    func clearFiles() {
        selectedFiles.removeAll()
        updateArchiveName()
    }
    
    private func updateArchiveName() {
        if selectedFiles.isEmpty {
            archiveName = ""
        } else {
            archiveName = fileService.generateSmartArchiveName(for: selectedFiles)
        }
    }
    
    // MARK: - Archive Operations
    
    func createArchive() {
        // Check 7-Zip availability first
        let status = sevenZipService.getInstallationStatus()
        if !status.isInstalled {
            setError(status.message)
            return
        }
        
        guard !selectedFiles.isEmpty else {
            setError("No files selected for archiving")
            return
        }
        
        guard !archiveName.isEmpty else {
            setError("Archive name cannot be empty")
            return
        }
        
        // Validate password if enabled
        if usePassword {
            // Check format compatibility with password protection
            if archiveFormat == "tar" {
                setError("TAR format does not support password protection. Please use 7z or ZIP format, or disable password protection.")
                return
            }
            
            guard !password.isEmpty else {
                setError("Password cannot be empty")
                return
            }
            
            guard password == confirmPassword else {
                setError("Passwords do not match")
                return
            }
            
            guard password.count >= 4 else {
                setError("Password must be at least 4 characters")
                return
            }
        }
        
        let outputPath = getOutputPath()
        
        // Validate output path for security
        let outputValidation = fileService.validateOutputPath(outputPath)
        if !outputValidation.isValid {
            setError(outputValidation.message ?? "Invalid output path")
            return
        }
        
        // Check disk space
        let estimatedSize = fileService.estimateArchiveSize(for: selectedFiles, compressionLevel: Int(compressionLevel))
        let spaceCheck = fileService.checkDiskSpace(for: outputPath, estimatedSize: estimatedSize)
        
        if !spaceCheck.hasSpace {
            setError(spaceCheck.message ?? "Insufficient disk space")
            return
        }
        
        if spaceCheck.message != nil {
            // Show warning but continue - could be logged or shown to user if needed
        }
        
        // Start operation
        setOperationRunning(true, message: "Creating archive...")
        
        sevenZipService.createArchive(
            files: selectedFiles,
            outputPath: outputPath,
            compressionLevel: Int(compressionLevel),
            password: usePassword ? password : nil
        ) { [weak self] result in
            self?.setOperationRunning(false)
            
            switch result {
            case .success:
                self?.setSuccess("Archive created successfully")
                self?.updateLastUsedDirectory(outputPath)
            case .failure(let error):
                self?.setError("Archive creation failed: \(error.localizedDescription)")
            }
        }
    }
    
    func extractArchive() {
        // Check 7-Zip availability first
        let status = sevenZipService.getInstallationStatus()
        if !status.isInstalled {
            setError(status.message)
            return
        }
        
        // Check if we have multiple archives to extract
        if selectedArchives.count > 1 {
            extractMultipleArchives()
            return
        }
        
        guard !selectedArchive.isEmpty else {
            setError("No archive selected")
            return
        }
        
        guard !extractDestination.isEmpty else {
            setError("No extraction destination specified")
            return
        }
        
        // Create extraction directory if needed
        do {
            try FileManager.default.createDirectory(atPath: extractDestination, withIntermediateDirectories: true)
        } catch {
            setError("Cannot create extraction directory: \(error.localizedDescription)")
            return
        }
        
        setOperationRunning(true, message: "Extracting archive...")
        
        let filesToExtract = extractionMode == "selected" ? getSelectedFilePaths() : nil
        
        sevenZipService.extractArchive(
            archivePath: selectedArchive,
            destinationPath: extractDestination,
            selectedFiles: filesToExtract
        ) { [weak self] result in
            self?.setOperationRunning(false)
            
            switch result {
            case .success:
                self?.setSuccess("Archive extracted successfully")
                self?.updateLastUsedDirectory(self?.extractDestination ?? "")
                self?.handleAutoOpen()
            case .failure(let error):
                switch error as? SevenZipError {
                case .passwordRequired:
                    self?.pendingPasswordOperation = .extractArchive
                    self?.isPasswordPromptVisible = true
                default:
                    self?.setError("Extraction failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func extractMultipleArchives() {
        guard !extractDestination.isEmpty else {
            setError("No extraction destination specified")
            return
        }
        
        // Create extraction directory if needed
        do {
            try FileManager.default.createDirectory(atPath: extractDestination, withIntermediateDirectories: true)
        } catch {
            setError("Cannot create extraction directory: \(error.localizedDescription)")
            return
        }
        
        setOperationRunning(true, message: "Extracting \(selectedArchives.count) archives...")
        
        // Process archives sequentially using a state class
        let state = MultiArchiveExtractionState(
            archives: selectedArchives,
            destination: extractDestination,
            mode: multiArchiveExtractionMode
        )
        
        processNextArchive(state: state)
    }
    
    private class MultiArchiveExtractionState {
        let archives: [String]
        let destination: String
        let mode: String
        var index: Int = 0
        var successCount: Int = 0
        var failedArchives: [(String, String)] = []
        
        init(archives: [String], destination: String, mode: String) {
            self.archives = archives
            self.destination = destination
            self.mode = mode
        }
        
        var totalArchives: Int {
            archives.count
        }
        
        var isComplete: Bool {
            index >= archives.count
        }
    }
    
    private func processNextArchive(state: MultiArchiveExtractionState) {
        guard !state.isComplete else {
            handleMultiArchiveCompletion(state: state)
            return
        }
        
        let archivePath = state.archives[state.index]
        let archiveName = (archivePath as NSString).lastPathComponent
        let archiveBaseName = (archiveName as NSString).deletingPathExtension
        
        // Determine destination based on mode
        let destination: String
        if state.mode == "separate" {
            destination = (state.destination as NSString).appendingPathComponent(archiveBaseName)
        } else {
            destination = state.destination
        }
        
        // Create destination directory
        do {
            try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
        } catch {
            state.failedArchives.append((archiveName, error.localizedDescription))
            state.index += 1
            processNextArchive(state: state)
            return
        }
        
        // Update progress message
        setOperationMessage("Extracting \(state.index + 1) of \(state.totalArchives): \(archiveName)")
        
        // Extract archive
        sevenZipService.extractArchive(
            archivePath: archivePath,
            destinationPath: destination,
            selectedFiles: nil
        ) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success:
                state.successCount += 1
            case .failure(let error):
                state.failedArchives.append((archiveName, error.localizedDescription))
            }
            
            state.index += 1
            self.processNextArchive(state: state)
        }
    }
    
    private func handleMultiArchiveCompletion(state: MultiArchiveExtractionState) {
        setOperationRunning(false)
        
        if state.successCount == state.totalArchives {
            setSuccess("All \(state.totalArchives) archives extracted successfully")
            updateLastUsedDirectory(extractDestination)
            handleAutoOpen()
        } else if state.successCount > 0 {
            var message = "\(state.successCount) of \(state.totalArchives) archives extracted successfully"
            if !state.failedArchives.isEmpty {
                message += "\n\nFailed archives:\n"
                for (name, error) in state.failedArchives {
                    message += "• \(name): \(error)\n"
                }
            }
            setError(message)
        } else {
            var message = "All archives failed to extract"
            if !state.failedArchives.isEmpty {
                message += "\n\n"
                for (name, error) in state.failedArchives {
                    message += "• \(name): \(error)\n"
                }
            }
            setError(message)
        }
    }
    
    private func setOperationMessage(_ message: String) {
        currentOperation = message
    }
    
    func extractSelectedFiles() {
        extractionMode = "selected"
        extractArchive()
    }
    
    private func extractArchiveWithPassword(_ password: String) {
        setOperationRunning(true, message: "Extracting archive...")
        
        let filesToExtract = extractionMode == "selected" ? getSelectedFilePaths() : nil
        
        sevenZipService.extractArchive(
            archivePath: selectedArchive,
            destinationPath: extractDestination,
            selectedFiles: filesToExtract,
            password: password
        ) { [weak self] result in
            self?.setOperationRunning(false)
            
            switch result {
            case .success:
                self?.setSuccess("Archive extracted successfully")
                self?.updateLastUsedDirectory(self?.extractDestination ?? "")
                self?.handleAutoOpen()
            case .failure(let error):
                self?.setError("Extraction failed: \(error.localizedDescription)")
            }
        }
    }
    
    func viewArchiveContents(password: String? = nil) {
        // Check 7-Zip availability first
        let status = sevenZipService.getInstallationStatus()
        if !status.isInstalled {
            setError(status.message)
            return
        }
        
        guard !selectedArchive.isEmpty else {
            setError("No archive selected")
            return
        }
        
        setOperationRunning(true, message: "Loading archive contents...")
        
        sevenZipService.listArchiveContents(archivePath: selectedArchive, password: password) { [weak self] result in
            self?.setOperationRunning(false)
            
            switch result {
            case .success(let files):
                self?.selectableFiles = files
                self?.fileTreeNodes = FileTreeBuilder.buildTree(from: files)
                self?.archiveContents = files.map { $0.path }
                self?.setSuccess("Archive contents loaded")
            case .failure(let error):
                switch error as? SevenZipError {
                case .passwordRequired:
                    self?.pendingPasswordOperation = .viewArchive
                    self?.isPasswordPromptVisible = true
                default:
                    self?.setError("Failed to load archive contents: \(error.localizedDescription)")
                }
            }
        }
    }

    func submitPassword() {
        isPasswordPromptVisible = false
        
        guard let operation = pendingPasswordOperation else {
            setError("No pending password operation")
            return
        }
        
        switch operation {
        case .viewArchive:
            viewArchiveContents(password: archivePassword)
        case .extractArchive:
            extractArchiveWithPassword(archivePassword)
        }
        
        // Clear the pending operation and password
        pendingPasswordOperation = nil
        archivePassword = ""
    }
    
    func loadSelectableFiles() {
        viewArchiveContents()
    }
    
    // MARK: - File Selection for Extraction
    
    func toggleFileSelection(_ index: Int) {
        if selectedFileIndices.contains(index) {
            selectedFileIndices.remove(index)
        } else {
            selectedFileIndices.insert(index)
        }
    }
    
    func selectAllFiles() {
        selectedFileIndices = Set(0..<selectableFiles.count)
    }
    
    func deselectAllFiles() {
        selectedFileIndices.removeAll()
    }
    
    // MARK: - Tree-based File Selection
    
    func toggleNodeSelection(_ node: FileTreeNode) {
        let indices = node.getAllFileIndices()
        
        // Check if all files in this node are selected
        let allSelected = indices.allSatisfy { selectedFileIndices.contains($0) }
        
        if allSelected {
            // Deselect all
            indices.forEach { selectedFileIndices.remove($0) }
        } else {
            // Select all
            indices.forEach { selectedFileIndices.insert($0) }
        }
    }
    
    func isNodeSelected(_ node: FileTreeNode) -> Bool {
        let indices = node.getAllFileIndices()
        guard !indices.isEmpty else { return false }
        return indices.allSatisfy { selectedFileIndices.contains($0) }
    }
    
    func isNodePartiallySelected(_ node: FileTreeNode) -> Bool {
        let indices = node.getAllFileIndices()
        guard !indices.isEmpty else { return false }
        let selectedCount = indices.filter { selectedFileIndices.contains($0) }.count
        return selectedCount > 0 && selectedCount < indices.count
    }
    
    private func getSelectedFilePaths() -> [String] {
        return selectedFileIndices.compactMap { index in
            guard index < selectableFiles.count else { return nil }
            return selectableFiles[index].path
        }
    }
    
    // MARK: - UI Support Methods
    
    func handleFileDrop(providers: [NSItemProvider]) {
        DragDropHandler.handleFileDrop(providers: providers) { [weak self] paths in
            self?.addFiles(paths)
        }
    }
    
    func handleArchiveDrop(providers: [NSItemProvider]) {
        DragDropHandler.handleArchiveDrop(providers: providers) { [weak self] path in
            if let path = path {
                self?.addArchive(path)
                self?.clearError()
            }
        }
    }
    
    func addArchive(_ path: String) {
        let cleanedPath = path.cleanedPath()
        
        // Set as primary archive if none selected
        if selectedArchive.isEmpty {
            selectedArchive = cleanedPath
        }
        
        // Add to multi-archive list if not already present
        if !selectedArchives.contains(cleanedPath) {
            selectedArchives.append(cleanedPath)
        }
    }
    
    func removeArchive(_ path: String) {
        selectedArchives.removeAll { $0 == path }
        
        // Update primary selection if removed
        if selectedArchive == path {
            selectedArchive = selectedArchives.first ?? ""
        }
    }
    
    func clearArchives() {
        selectedArchive = ""
        selectedArchives = []
    }
    
    func setArchiveOutputLocation(_ path: String) {
        archiveOutputLocation = path
    }
    
    func handleFileSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let paths = urls.map { $0.path }
            addFiles(paths)
        case .failure(let error):
            setError("File selection error: \(error.localizedDescription)")
        }
    }
    
    func handleArchiveSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            // Support multiple archive selection
            for url in urls {
                addArchive(url.path)
            }
            clearError()
        case .failure(let error):
            setError("Archive selection error: \(error.localizedDescription)")
        }
    }
    
    func chooseExtractionDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            extractDestination = url.path
        }
    }
    
    func openContainingFolder(_ path: String) {
        fileService.openContainingFolder(for: path)
    }
    
    func cancelOperation() {
        setOperationRunning(false)
        setSuccess("Operation cancelled")
    }
    
    // MARK: - Private Helper Methods
    
    private func getOutputPath() -> String {
        // Build the full filename with extension
        let fullFileName = getFullArchiveName()
        
        // Use custom location if set
        if let customLocation = archiveOutputLocation, !customLocation.isEmpty {
            return (customLocation as NSString).appendingPathComponent(fullFileName)
        }
        
        // Otherwise use preferences
        let prefs = userPreferences.preferences
        var defaultDir = prefs.rememberLastDirectory && !prefs.lastOutputDirectory.isEmpty 
            ? prefs.lastOutputDirectory 
            : prefs.defaultOutputDirectory
        
        // Safety fallback: if directory is empty, invalid, or not writable, use Desktop
        if defaultDir.isEmpty || !FileManager.default.isWritableFile(atPath: defaultDir) {
            defaultDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path
        }
        
        return (defaultDir as NSString).appendingPathComponent(fullFileName)
    }
    
    /// Returns the archive name with the appropriate file extension based on selected format
    private func getFullArchiveName() -> String {
        // Remove any existing archive extension from the name
        var baseName = archiveName
        let archiveExtensions = ["7z", "zip", "tar", "tar.gz", "tgz", "tar.bz2", "tbz2", "tar.xz", "txz"]
        for ext in archiveExtensions {
            if baseName.lowercased().hasSuffix(".\(ext)") {
                baseName = String(baseName.dropLast(ext.count + 1))
                break
            }
        }
        
        // Append the selected format extension
        return "\(baseName).\(archiveFormat)"
    }
    
    private func updateLastUsedDirectory(_ outputPath: String) {
        let directory = (outputPath as NSString).deletingLastPathComponent
        
        // Validate directory before saving - don't save /Volumes or other invalid paths
        // /Volumes is the mount point root and can't have files written directly to it
        if directory != "/Volumes" && !directory.isEmpty && FileManager.default.isWritableFile(atPath: directory) {
            userPreferences.preferences.lastOutputDirectory = directory
            userPreferences.savePreferences()
        }
    }
    
    private func handleAutoOpen() {
        if userPreferences.preferences.autoOpenAfterExtract {
            fileService.openContainingFolder(for: extractDestination)
        }
    }
    
    // MARK: - State Management
    
    private func setOperationRunning(_ running: Bool, message: String = "") {
        isOperationRunning = running
        currentOperation = message
        if running {
            clearError()
        }
    }
    
    private func setError(_ message: String) {
        errorMessage = message
        currentOperation = ""
    }
    
    private func setSuccess(_ message: String) {
        currentOperation = message
        errorMessage = ""
    }
    
    // MARK: - Preferences Integration
    
    func refreshFromPreferences() {
        applyCompressionPreferences()
        // Update extraction destination if needed
        let prefs = userPreferences.preferences
        if prefs.rememberLastDirectory && !prefs.lastOutputDirectory.isEmpty {
            extractDestination = prefs.lastOutputDirectory
        } else {
            extractDestination = prefs.defaultOutputDirectory
        }
    }
    
    private func clearError() {
        errorMessage = ""
    }
}
