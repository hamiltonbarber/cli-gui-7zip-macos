import SwiftUI
import UniformTypeIdentifiers

struct ExtractArchiveView: View {
    @ObservedObject var viewModel: ArchiveViewModel
    @State private var showingArchivePicker = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
            ArchiveSelectionSection(
                viewModel: viewModel,
                showingArchivePicker: $showingArchivePicker
            )
            
            if !viewModel.selectedArchive.isEmpty {
                ExtractionOptionsSection(viewModel: viewModel)
                
                if viewModel.extractionMode == "selected" && !viewModel.selectableFiles.isEmpty {
                    ExtractFileSelectionSection(viewModel: viewModel)
                }
                
                DestinationSection(viewModel: viewModel)
                ActionButtonsSection(viewModel: viewModel)
            }
            
            Spacer()
            }
        }
        .padding()
        .fileImporter(
            isPresented: $showingArchivePicker,
            allowedContentTypes: [.archive],
            allowsMultipleSelection: true
        ) { result in
            viewModel.handleArchiveSelection(result: result)
        }
    }
}

// MARK: - Archive Selection Section

struct ArchiveSelectionSection: View {
    @ObservedObject var viewModel: ArchiveViewModel
    @Binding var showingArchivePicker: Bool
    
    var body: some View {
        GroupBox("Archive(s) to Extract") {
            VStack {
                if viewModel.selectedArchives.isEmpty {
                    ArchiveDropZone(onDrop: viewModel.handleArchiveDrop)
                } else if viewModel.selectedArchives.count == 1 {
                    SelectedArchiveView(
                        archivePath: viewModel.selectedArchive,
                        onClear: { viewModel.clearArchives() }
                    )
                } else {
                    MultipleArchivesView(
                        archives: viewModel.selectedArchives,
                        onRemove: viewModel.removeArchive,
                        onClearAll: viewModel.clearArchives
                    )
                }
                
                HStack {
                    if viewModel.selectedArchives.count > 0 {
                        Text("\(viewModel.selectedArchives.count) archive(s) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Browse", action: { showingArchivePicker = true })
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}

struct ArchiveDropZone: View {
    let onDrop: ([NSItemProvider]) -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "archivebox")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Drop archive here or click Browse")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .dropZone { providers in
            onDrop(providers)
            return true
        }
    }
}

struct SelectedArchiveView: View {
    let archivePath: String
    let onClear: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "archivebox.fill")
                .foregroundStyle(.blue)
            Text(URL(fileURLWithPath: archivePath).lastPathComponent)
            Spacer()
            Button("Clear", action: onClear)
                .buttonStyle(.bordered)
        }
        .padding(8)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
}

struct MultipleArchivesView: View {
    let archives: [String]
    let onRemove: (String) -> Void
    let onClearAll: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Selected Archives")
                    .font(.headline)
                Spacer()
                Button("Clear All", action: onClearAll)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(archives, id: \.self) { archive in
                        HStack {
                            Image(systemName: "archivebox.fill")
                                .foregroundStyle(.blue)
                                .font(.caption)
                            Text(URL(fileURLWithPath: archive).lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Button(action: { onRemove(archive) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
            .frame(maxHeight: 150)
        }
    }
}

// MARK: - Extraction Options Section

struct ExtractionOptionsSection: View {
    @ObservedObject var viewModel: ArchiveViewModel
    
    var body: some View {
        GroupBox("Extraction Options") {
            VStack(alignment: .leading, spacing: 8) {
                // Multi-archive extraction mode (only show when multiple archives selected)
                if viewModel.selectedArchives.count > 1 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Multiple Archives Mode")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Picker("", selection: $viewModel.multiArchiveExtractionMode) {
                            Text("Separate folders (one per archive)").tag("separate")
                            Text("Combined (all in one folder)").tag("combined")
                        }
                        .pickerStyle(.radioGroup)
                        
                        if viewModel.multiArchiveExtractionMode == "separate" {
                            Text("Each archive will be extracted to its own folder")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 20)
                        } else {
                            Text("All archives will extract to the same folder")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 20)
                        }
                    }
                    
                    Divider()
                }
                
                // Single archive extraction mode
                if viewModel.selectedArchives.count == 1 {
                    Picker("Extract", selection: $viewModel.extractionMode) {
                        Text("All files").tag("all")
                        Text("Selected files").tag("selected")
                    }
                    .pickerStyle(.segmented)
                    
                    if viewModel.extractionMode == "selected" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Load archive details to select specific files")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Button("Load File List", action: viewModel.loadSelectableFiles)
                                .disabled(viewModel.isOperationRunning)
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - File Selection Section

struct ExtractFileSelectionSection: View {
    @ObservedObject var viewModel: ArchiveViewModel
    
    var body: some View {
        GroupBox("Select Files to Extract") {
            VStack(alignment: .leading, spacing: 8) {
                SelectionControlButtons(viewModel: viewModel)
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.fileTreeNodes, id: \.id) { node in
                            FileTreeNodeView(node: node, viewModel: viewModel, level: 0)
                        }
                    }
                }
                .frame(minHeight: 250, idealHeight: 350, maxHeight: 500)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
                .layoutPriority(1)
            }
        }
    }
}

struct FileTreeNodeView: View {
    @ObservedObject var node: FileTreeNode
    @ObservedObject var viewModel: ArchiveViewModel
    let level: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                // Indentation
                ForEach(0..<level, id: \.self) { _ in
                    Spacer().frame(width: 20)
                }
                
                // Expand/collapse button for directories
                if node.isDirectory && !node.children.isEmpty {
                    Button(action: { node.isExpanded.toggle() }) {
                        Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 12)
                }
                
                // Selection checkbox
                Button(action: { viewModel.toggleNodeSelection(node) }) {
                    if viewModel.isNodePartiallySelected(node) {
                        Image(systemName: "minus.square")
                            .foregroundStyle(.blue)
                    } else {
                        Image(systemName: viewModel.isNodeSelected(node) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(viewModel.isNodeSelected(node) ? .blue : .secondary)
                    }
                }
                .buttonStyle(.plain)
                
                // Icon
                Image(systemName: node.isDirectory ? "folder.fill" : "doc")
                    .foregroundStyle(node.isDirectory ? .blue : .primary)
                    .font(.caption)
                
                // Name and info
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(node.displaySize)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let date = node.modificationDate {
                            Text(DateFormatter.fileDate.string(from: date))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            
            // Recursively show children if expanded
            if node.isExpanded {
                ForEach(node.children) { child in
                    FileTreeNodeView(node: child, viewModel: viewModel, level: level + 1)
                }
            }
        }
    }
}

struct SelectionControlButtons: View {
    @ObservedObject var viewModel: ArchiveViewModel
    
    var body: some View {
        HStack {
            Button("Select All", action: viewModel.selectAllFiles)
                .buttonStyle(.bordered)
            
            Button("Deselect All", action: viewModel.deselectAllFiles)
                .buttonStyle(.bordered)
            
            Spacer()
            
            Text("\(viewModel.selectedFileIndices.count) of \(viewModel.selectableFiles.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct FileSelectionRow: View {
    let index: Int
    let file: ArchiveFileInfo
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            
            Image(systemName: file.isDirectory ? "folder" : "doc")
                .foregroundStyle(file.isDirectory ? .blue : .primary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(file.path)
                    .lineLimit(1)
                HStack {
                    Text(file.displaySize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let date = file.modificationDate {
                        Text(DateFormatter.fileDate.string(from: date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
}
// MARK: - Destination Section

struct DestinationSection: View {
    @ObservedObject var viewModel: ArchiveViewModel
    
    var body: some View {
        GroupBox("Extract to") {
            HStack {
                TextField("Destination folder", text: $viewModel.extractDestination)
                Button("Browse", action: viewModel.chooseExtractionDestination)
            }
            .padding(8)
        }
    }
}

// MARK: - Action Buttons Section

struct ActionButtonsSection: View {
    @ObservedObject var viewModel: ArchiveViewModel
    
    var body: some View {
        HStack {
            Button("Preview Archive") {
                viewModel.viewArchiveContents()
            }
                .disabled(viewModel.isOperationRunning)
            
            Spacer()
            
            Button("Extract") {
                if viewModel.extractionMode == "selected" {
                    viewModel.extractSelectedFiles()
                } else {
                    viewModel.extractArchive()
                }
            }
            .disabled(viewModel.selectedArchive.isEmpty || viewModel.isOperationRunning)
            .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $viewModel.isPasswordPromptVisible) {
            PasswordPromptView(viewModel: viewModel)
        }
    }
}
