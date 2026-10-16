import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Declared in project.yml (UTExportedTypeDeclarations), so only Repaso's own targets accept these drags.
    static let repasoDragRef = UTType(exportedAs: "com.amudgal.repaso.drag-ref", conformingTo: .data)
}

struct DragRef: Codable, Hashable, Transferable {
    enum Kind: String, Codable { case folder, clip }
    let kind: Kind
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .repasoDragRef)
    }
}
