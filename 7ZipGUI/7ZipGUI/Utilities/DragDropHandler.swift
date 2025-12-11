import SwiftUI
import UniformTypeIdentifiers

struct DragDropHandler {
    static func handleFileDrop(
        providers: [NSItemProvider],
        completion: @escaping ([String]) -> Void
    ) {
        var paths: [String] = []
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { (urlData, error) in
                defer { group.leave() }
                
                if let urlData = urlData as? Data,
                   let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                    paths.append(url.path)
                }
            }
        }
        
        group.notify(queue: .main) {
            completion(paths)
        }
    }
    
    static func handleArchiveDrop(
        providers: [NSItemProvider],
        completion: @escaping (String?) -> Void
    ) {
        handleFileDrop(providers: providers) { paths in
            completion(paths.first)
        }
    }
}

// MARK: - Drop Zone View Modifier

struct DropZone: ViewModifier {
    let isTargeted: Binding<Bool>?
    let onDrop: ([NSItemProvider]) -> Bool
    
    func body(content: Content) -> some View {
        content
            .onDrop(of: [UTType.fileURL], isTargeted: isTargeted) { providers in
                return onDrop(providers)
            }
    }
}

extension View {
    func dropZone(
        isTargeted: Binding<Bool>? = nil,
        onDrop: @escaping ([NSItemProvider]) -> Bool
    ) -> some View {
        modifier(DropZone(isTargeted: isTargeted, onDrop: onDrop))
    }
}
