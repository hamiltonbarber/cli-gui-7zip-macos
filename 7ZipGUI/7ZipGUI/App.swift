import SwiftUI

@main
struct SevenZipGUIApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Archive...") {
                    // Handle opening archive
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
