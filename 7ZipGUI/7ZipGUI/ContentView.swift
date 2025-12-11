import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = ArchiveViewModel()
    @State private var selectedTab = 0
    @State private var showingPreferences = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Preferences Button
            HStack {
                Text("GUI for 7-Zip")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Preferences") {
                    showingPreferences = true
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            // Tab Selector
            Picker("Operation", selection: $selectedTab) {
                Text("Create Archive").tag(0)
                Text("Extract Archive").tag(1)
                Text("View Archive").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            TabView(selection: $selectedTab) {
                CreateArchiveView(viewModel: viewModel)
                    .tag(0)
                
                ExtractArchiveView(viewModel: viewModel)
                    .tag(1)
                
                ViewArchiveView(viewModel: viewModel)
                    .tag(2)
            }
            
            // Status Area
            StatusBarView(viewModel: viewModel)
        }
        .frame(minWidth: 600, minHeight: 500)
        .sheet(isPresented: $showingPreferences) {
            UserPreferencesView(
                preferencesService: viewModel.userPreferences,
                viewModel: viewModel
            )
        }
    }
}

// MARK: - Status Bar Component

struct StatusBarView: View {
    @ObservedObject var viewModel: ArchiveViewModel
    
    var body: some View {
        if viewModel.isOperationRunning || !viewModel.currentOperation.isEmpty || !viewModel.errorMessage.isEmpty {
            VStack {
                Divider()
                
                if !viewModel.errorMessage.isEmpty {
                    ErrorView(message: viewModel.errorMessage) {
                        viewModel.errorMessage = ""
                    }
                } else {
                    OperationStatusView(viewModel: viewModel)
                }
            }
            .padding()
        }
    }
}

struct ErrorView: View {
    let message: String
    let onDismiss: () -> Void
    @State private var showingDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                
                if message.contains("7-Zip not installed") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("7-Zip Required")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.red)
                        
                        if showingDetails {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        } else {
                            Text("7-Zip not found. Click 'Show Details' for installation instructions.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                } else {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                
                Spacer()
                
                if message.contains("7-Zip not installed") {
                    Button(showingDetails ? "Hide Details" : "Show Details") {
                        showingDetails.toggle()
                    }
                    .buttonStyle(.link)
                }
                
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.link)
            }
        }
    }
}

struct OperationStatusView: View {
    @ObservedObject var viewModel: ArchiveViewModel
    
    var body: some View {
        HStack {
            if viewModel.isOperationRunning {
                ProgressView()
                    .scaleEffect(0.8)
                Text(viewModel.currentOperation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !viewModel.currentOperation.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(viewModel.currentOperation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if viewModel.currentOperation.contains("successfully") {
                    Button("Open Folder") {
                        viewModel.openContainingFolder(viewModel.extractDestination)
                    }
                    .buttonStyle(.link)
                }
            }
            
            Spacer()
            
            if viewModel.isOperationRunning {
                Button("Cancel", action: viewModel.cancelOperation)
                    .buttonStyle(.bordered)
            }
        }
    }
}

#Preview {
    ContentView()
}
