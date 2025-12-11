import SwiftUI
import UniformTypeIdentifiers

struct ViewArchiveView: View {
    @ObservedObject var viewModel: ArchiveViewModel
    @State private var showingArchivePicker = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ArchiveViewSelectionSection(
                    viewModel: viewModel,
                    showingArchivePicker: $showingArchivePicker
                )
                
                if !viewModel.selectableFiles.isEmpty {
                    ArchiveContentsSection(viewModel: viewModel)
                }
                
                Spacer()
            }
        }
        .padding()
        .fileImporter(
            isPresented: $showingArchivePicker,
            allowedContentTypes: [.archive],
            allowsMultipleSelection: false
        ) { result in
            viewModel.handleArchiveSelection(result: result)
        }
        .sheet(isPresented: $viewModel.isPasswordPromptVisible) {
            PasswordPromptView(viewModel: viewModel)
        }
    }
}

// MARK: - Archive Selection Section

struct ArchiveViewSelectionSection: View {
    @ObservedObject var viewModel: ArchiveViewModel
    @Binding var showingArchivePicker: Bool
    
    var body: some View {
        GroupBox("Archive to View") {
            VStack {
                if viewModel.selectedArchive.isEmpty {
                    ViewArchiveDropZone(onDrop: viewModel.handleArchiveDrop)
                } else {
                    ViewSelectedArchiveView(
                        archivePath: viewModel.selectedArchive,
                        onClear: {
                            viewModel.selectedArchive = ""
                            viewModel.selectableFiles = []
                        }
                    )
                }
                
                HStack {
                    Spacer()
                    
                    Button("Browse") {
                        showingArchivePicker = true
                    }
                    .buttonStyle(.bordered)
                    
                    if !viewModel.selectedArchive.isEmpty {
                        Button("View Contents") {
                            viewModel.viewArchiveContents()
                        }
                        .disabled(viewModel.isOperationRunning)
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
}

struct ViewArchiveDropZone: View {
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

struct ViewSelectedArchiveView: View {
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

// MARK: - Archive Contents Section

struct ArchiveContentsSection: View {
    @ObservedObject var viewModel: ArchiveViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Archive Contents")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.selectableFiles.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(viewModel.selectableFiles.enumerated()), id: \.offset) { index, file in
                        ArchiveFileRow(file: file)
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
            .frame(minHeight: 250, idealHeight: 350, maxHeight: 500)
            .layoutPriority(1)
        }
    }
}

struct ArchiveFileRow: View {
    let file: ArchiveFileInfo
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.isDirectory ? "folder.fill" : "doc.text.fill")
                .foregroundStyle(file.isDirectory ? .blue : .primary)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(file.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                HStack {
                    Text(file.displaySize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let date = file.modificationDate {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.clear)
        .contentShape(Rectangle())
    }
}