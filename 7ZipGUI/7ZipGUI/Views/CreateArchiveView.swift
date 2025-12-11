import SwiftUI
import UniformTypeIdentifiers

struct CreateArchiveView: View {
    @ObservedObject var viewModel: ArchiveViewModel
    @State private var showingFilePicker = false
    
    var body: some View {
        HSplitView {
            CreateFileSelectionSection(viewModel: viewModel, showingFilePicker: $showingFilePicker)
            ArchiveSettingsSection(viewModel: viewModel)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            viewModel.handleFileSelection(result: result)
        }
    }
}

// MARK: - File Selection Section

struct CreateFileSelectionSection: View {
    @ObservedObject var viewModel: ArchiveViewModel
    @Binding var showingFilePicker: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Files to Archive")
                .font(.headline)
            
            if viewModel.selectedFiles.isEmpty {
                EmptyFileDropZone(onDrop: viewModel.handleFileDrop)
            } else {
                FilledFileList(viewModel: viewModel)
            }
            
            FileSelectionButtons(
                showingFilePicker: $showingFilePicker,
                hasFiles: !viewModel.selectedFiles.isEmpty,
                onClearFiles: viewModel.clearFiles
            )
        }
        .padding()
    }
}

struct EmptyFileDropZone: View {
    let onDrop: ([NSItemProvider]) -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Drop files here or click Browse")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 200)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .dropZone { providers in
            onDrop(providers)
            return true
        }
    }
}

struct FilledFileList: View {
    @ObservedObject var viewModel: ArchiveViewModel
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(viewModel.selectedFiles, id: \.self) { file in
                    FileListRow(
                        fileName: URL(fileURLWithPath: file).lastPathComponent,
                        onRemove: { viewModel.removeFile(file) }
                    )
                }
            }
        }
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
        .frame(minHeight: 200)
    }
}

struct FileListRow: View {
    let fileName: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "doc")
            Text(fileName)
            Spacer()
            Button("Remove", action: onRemove)
                .buttonStyle(.plain)
                .foregroundStyle(.red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}

struct FileSelectionButtons: View {
    @Binding var showingFilePicker: Bool
    let hasFiles: Bool
    let onClearFiles: () -> Void
    
    var body: some View {
        HStack {
            Button("Browse Files") {
                showingFilePicker = true
            }
            
            if hasFiles {
                Button("Clear All", action: onClearFiles)
                    .foregroundStyle(.red)
            }
        }
    }
}
// MARK: - Archive Settings Section

struct ArchiveSettingsSection: View {
    @ObservedObject var viewModel: ArchiveViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Archive Settings")
                .font(.headline)
            
            OutputSettingsGroup(viewModel: viewModel)
            CompressionSettingsGroup(viewModel: viewModel)
            SecuritySettingsGroup(viewModel: viewModel)
            
            Spacer()
            
            CreateArchiveButton(viewModel: viewModel)
        }
        .padding()
    }
}

struct OutputSettingsGroup: View {
    @ObservedObject var viewModel: ArchiveViewModel
    @State private var showingLocationPicker = false
    
    var body: some View {
        GroupBox("Output") {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Archive Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Enter name (e.g., MyArchive)", text: $viewModel.archiveName)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Save Location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Browse...") {
                            showingLocationPicker = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    if let location = getArchiveLocation() {
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)
                    } else {
                        Text("Will save next to source files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Picker("Format", selection: $viewModel.archiveFormat) {
                    Text("7z (recommended)").tag("7z")
                    Text("ZIP").tag("zip")
                    Text("TAR").tag("tar")
                }
                .pickerStyle(MenuPickerStyle())
            }
        }
        .fileImporter(
            isPresented: $showingLocationPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.setArchiveOutputLocation(url.path)
                }
            case .failure:
                break
            }
        }
    }
    
    private func getArchiveLocation() -> String? {
        // Get the custom location if set, otherwise nil
        return viewModel.archiveOutputLocation
    }
}

struct CompressionSettingsGroup: View {
    @ObservedObject var viewModel: ArchiveViewModel
    
    var body: some View {
        GroupBox("Compression") {
            VStack(alignment: .leading, spacing: 8) {
                // Show current preference setting
                let currentPreset = viewModel.userPreferences.preferences.compressionPreset
                if currentPreset != "custom" {
                    HStack {
                        Text("Preference:")
                        Text(presetDisplayName(currentPreset))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Override") {
                            // Don't change preference, just enable UI override
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
                
                HStack {
                    Text("Level:")
                    Slider(value: $viewModel.compressionLevel, in: 0...9, step: 1)
                        .onChange(of: viewModel.compressionLevel) { _ in
                            // When user changes slider, we're overriding preferences
                        }
                    Text("\(Int(viewModel.compressionLevel))")
                        .frame(width: 20)
                }
                
                Text(compressionDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func presetDisplayName(_ preset: String) -> String {
        switch preset {
        case "fast": return "Fast (Level 1)"
        case "balanced": return "Balanced (Level 5)"
        case "maximum": return "Maximum (Level 9)"
        default: return preset.capitalized
        }
    }
    
    private var compressionDescription: String {
        switch Int(viewModel.compressionLevel) {
        case 0: return "Store (no compression)"
        case 1...3: return "Fast compression"
        case 4...6: return "Normal compression"
        case 7...8: return "Maximum compression"
        case 9: return "Ultra compression (slow)"
        default: return ""
        }
    }
}

struct SecuritySettingsGroup: View {
    @ObservedObject var viewModel: ArchiveViewModel
    
    var body: some View {
        GroupBox("Security") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Password protection", isOn: $viewModel.usePassword)
                
                if viewModel.usePassword {
                    SecureField("Password", text: $viewModel.password)
                    SecureField("Confirm password", text: $viewModel.confirmPassword)
                }
            }
        }
    }
}

struct CreateArchiveButton: View {
    @ObservedObject var viewModel: ArchiveViewModel
    
    var body: some View {
        Button("Create Archive", action: viewModel.createArchive)
            .disabled(viewModel.selectedFiles.isEmpty || viewModel.isOperationRunning)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
    }
}
