import SwiftUI

struct UserPreferencesView: View {
    @ObservedObject var preferencesService: UserPreferencesService
    @ObservedObject var viewModel: ArchiveViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 16) {
                        CompressionPreferencesSection(preferences: $preferencesService.preferences)
                        Divider()
                        DirectoryPreferencesSection(preferences: $preferencesService.preferences)
                        Divider()
                        AutoOpenPreferencesSection(preferences: $preferencesService.preferences)
                        Divider()
                        ExclusionPreferencesSection(preferences: $preferencesService.preferences)
                    }
                    .padding()
                    
                    HStack {
                        Button("Reset to Defaults") {
                            preferencesService.resetPreferences()
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button("Cancel") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Save") {
                            preferencesService.savePreferences()
                            viewModel.refreshFromPreferences()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
            .navigationTitle("User Preferences")
            .frame(minWidth: 600, maxWidth: 800, minHeight: 500, maxHeight: 700)
        }
        .frame(minWidth: 600, maxWidth: 800, minHeight: 500, maxHeight: 700)
    }
}

// MARK: - Compression Preferences Section

struct CompressionPreferencesSection: View {
    @Binding var preferences: UserPreferences
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compression Settings")
                .font(.headline)
                .foregroundStyle(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Default Compression:")
                    Spacer()
                    Picker("Default Compression", selection: $preferences.compressionPreset) {
                        Text("Fast (Level 1)").tag("fast")
                        Text("Balanced (Level 5)").tag("balanced")  
                        Text("Maximum (Level 9)").tag("maximum")
                        Text("Custom Level").tag("custom")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                }
                
                if preferences.compressionPreset == "custom" {
                    HStack {
                        Text("Custom Level:")
                        Slider(value: Binding(
                            get: { Double(preferences.customCompressionLevel) },
                            set: { preferences.customCompressionLevel = Int($0) }
                        ), in: 0...9, step: 1)
                        Text("\(preferences.customCompressionLevel)")
                            .frame(width: 30)
                    }
                }
                
                Text(compressionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
    }
    
    private var compressionDescription: String {
        switch preferences.compressionPreset {
        case "fast": return "Always use fast compression (Level 1)"
        case "balanced": return "Always use balanced compression (Level 5)"
        case "maximum": return "Always use maximum compression (Level 9)"
        case "custom": return "Always use custom level (\(preferences.customCompressionLevel))"
        default: return ""
        }
    }
}

// MARK: - Directory Preferences Section

struct DirectoryPreferencesSection: View {
    @Binding var preferences: UserPreferences
    @State private var showingDirectoryPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Directory Settings")
                .font(.headline)
                .foregroundStyle(.primary)
            
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Default Output Directory:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        Text(preferences.defaultOutputDirectory)
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Button("Browse") {
                            showingDirectoryPicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                Toggle("Remember Last Used Directory", isOn: $preferences.rememberLastDirectory)
                
                if preferences.rememberLastDirectory && !preferences.lastOutputDirectory.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last Used Directory:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(preferences.lastOutputDirectory)
                            .font(.caption)
                            .textSelection(.enabled)
                            .padding(6)
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(4)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
        .fileImporter(
            isPresented: $showingDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    preferences.defaultOutputDirectory = url.path
                }
            case .failure:
                break
            }
        }
    }
}

// MARK: - Auto-Open Preferences Section

struct AutoOpenPreferencesSection: View {
    @Binding var preferences: UserPreferences
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extraction Behavior")
                .font(.headline)
                .foregroundStyle(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Auto-open folder after extraction", isOn: $preferences.autoOpenAfterExtract)
                
                Text("When enabled, the containing folder will automatically open after successful extraction")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
    }
}

// MARK: - Exclusion Preferences Section

struct ExclusionPreferencesSection: View {
    @Binding var preferences: UserPreferences
    @State private var newPattern = ""
    @State private var showingAddPattern = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("File Exclusions")
                .font(.headline)
                .foregroundStyle(.primary)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Files matching these patterns will be excluded from archives:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if preferences.excludePatterns.isEmpty {
                    Text("No exclusion patterns set")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(preferences.excludePatterns.enumerated()), id: \.offset) { index, pattern in
                        HStack {
                            Text(pattern)
                                .font(.system(.body, design: .monospaced))
                                .padding(.vertical, 4)
                            Spacer()
                            Button("Remove") {
                                preferences.excludePatterns.remove(at: index)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(4)
                    }
                }
                
                if showingAddPattern {
                    HStack {
                        TextField("Pattern (e.g., *.tmp)", text: $newPattern)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Add") {
                            if !newPattern.isEmpty && !preferences.excludePatterns.contains(newPattern) {
                                preferences.excludePatterns.append(newPattern)
                                newPattern = ""
                                showingAddPattern = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Cancel") {
                            newPattern = ""
                            showingAddPattern = false
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Button("Add Pattern") {
                        showingAddPattern = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
    }
}

#Preview {
    UserPreferencesView(
        preferencesService: UserPreferencesService(),
        viewModel: ArchiveViewModel()
    )
}
