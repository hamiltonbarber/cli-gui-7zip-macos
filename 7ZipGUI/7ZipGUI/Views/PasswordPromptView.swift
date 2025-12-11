import SwiftUI

struct PasswordPromptView: View {
    @ObservedObject var viewModel: ArchiveViewModel

    var body: some View {
        VStack {
            Text("Enter Password")
                .font(.headline)
            SecureField("Password", text: $viewModel.archivePassword)
            HStack {
                Button("Cancel") {
                    viewModel.isPasswordPromptVisible = false
                }
                .buttonStyle(.bordered)
                Button("Submit") {
                    viewModel.submitPassword()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}