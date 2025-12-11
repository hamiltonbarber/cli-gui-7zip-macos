import Foundation

class FileTreeNode: Identifiable, ObservableObject {
    let id = UUID()
    let name: String
    let fullPath: String
    let isDirectory: Bool
    let size: Int64
    let modificationDate: Date?
    let fileIndex: Int?  // Index in original flat list (nil for synthetic folders)
    
    @Published var isExpanded: Bool = false
    @Published var children: [FileTreeNode] = []
    
    var parent: FileTreeNode?
    
    init(name: String, fullPath: String, isDirectory: Bool, size: Int64 = 0, modificationDate: Date? = nil, fileIndex: Int? = nil) {
        self.name = name
        self.fullPath = fullPath
        self.isDirectory = isDirectory
        self.size = size
        self.modificationDate = modificationDate
        self.fileIndex = fileIndex
    }
    
    var displaySize: String {
        if isDirectory { return "Folder" }
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024) }
        if size < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(size) / (1024 * 1024)) }
        return String(format: "%.1f GB", Double(size) / (1024 * 1024 * 1024))
    }
    
    // Get all file indices in this node and its children
    func getAllFileIndices() -> [Int] {
        var indices: [Int] = []
        if let index = fileIndex {
            indices.append(index)
        }
        for child in children {
            indices.append(contentsOf: child.getAllFileIndices())
        }
        return indices
    }
}

// Helper to build tree from flat file list
class FileTreeBuilder {
    static func buildTree(from files: [ArchiveFileInfo]) -> [FileTreeNode] {
        var rootNodes: [FileTreeNode] = []
        var pathToNode: [String: FileTreeNode] = [:]
        
        for (index, file) in files.enumerated() {
            let pathComponents = file.path.split(separator: "/").map(String.init)
            
            if pathComponents.isEmpty { continue }
            
            var currentPath = ""
            var currentParent: FileTreeNode? = nil
            
            for (componentIndex, component) in pathComponents.enumerated() {
                let isLast = componentIndex == pathComponents.count - 1
                currentPath = currentPath.isEmpty ? component : currentPath + "/" + component
                
                if let existingNode = pathToNode[currentPath] {
                    currentParent = existingNode
                } else {
                    let newNode = FileTreeNode(
                        name: component,
                        fullPath: currentPath,
                        isDirectory: isLast ? file.isDirectory : true,
                        size: isLast ? file.size : 0,
                        modificationDate: isLast ? file.modificationDate : nil,
                        fileIndex: isLast ? index : nil
                    )
                    
                    pathToNode[currentPath] = newNode
                    
                    if let parent = currentParent {
                        newNode.parent = parent
                        parent.children.append(newNode)
                    } else {
                        rootNodes.append(newNode)
                    }
                    
                    currentParent = newNode
                }
            }
        }
        
        return rootNodes
    }
}
