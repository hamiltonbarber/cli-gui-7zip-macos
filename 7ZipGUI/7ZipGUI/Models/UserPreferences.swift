import Foundation

struct UserPreferences: Codable {
    var compressionPreset: String = "balanced"
    var customCompressionLevel: Int = 5
    var defaultOutputDirectory: String = ""
    var autoOpenAfterExtract: Bool = false
    var excludePatterns: [String] = [".DS_Store", ".Thumbs.db", "Thumbs.db"]
    var rememberLastDirectory: Bool = true
    var lastOutputDirectory: String = ""
    
    init() {
        defaultOutputDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path
    }
}

extension UserPreferences {
    static let shared = UserPreferencesService()
}

class UserPreferencesService: ObservableObject {
    @Published var preferences: UserPreferences = UserPreferences()
    
    private let preferencesURL: URL = {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("7zip_gui_preferences.json")
    }()
    
    init() {
        loadPreferences()
    }
    
    func loadPreferences() {
        do {
            let data = try Data(contentsOf: preferencesURL)
            preferences = try JSONDecoder().decode(UserPreferences.self, from: data)
            
            // Safety check: ensure defaultOutputDirectory is never empty
            if preferences.defaultOutputDirectory.isEmpty {
                preferences.defaultOutputDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path
                savePreferences()
            }
        } catch {
            preferences = UserPreferences()
            savePreferences()
        }
    }
    
    func savePreferences() {
        do {
            let data = try JSONEncoder().encode(preferences)
            try data.write(to: preferencesURL)
        } catch {
            print("Failed to save preferences: \(error.localizedDescription)")
        }
    }
    
    func resetPreferences() {
        preferences = UserPreferences()
        savePreferences()
    }
}
