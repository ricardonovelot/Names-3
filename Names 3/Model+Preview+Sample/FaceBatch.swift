import Foundation
import SwiftData

@Model
final class FaceBatch {
    var createdAt: Date = Date()
    var date: Date = Date()
    var image: Data = Data()
    var groupName: String = ""

    var faces: [FaceBatchFace]? = []

    init(
        createdAt: Date = Date(),
        date: Date = Date(),
        image: Data = Data(),
        groupName: String = "",
        faces: [FaceBatchFace]? = []
    ) {
        self.createdAt = createdAt
        self.date = date
        self.image = image
        self.groupName = groupName
        self.faces = faces
    }
}

@Model
final class FaceBatchFace {
    var uuid: UUID = UUID()
    var order: Int = 0
    var assignedName: String = ""
    var thumbnail: Data = Data()
    var exported: Bool = false

    @Relationship(inverse: \FaceBatch.faces)
    var batch: FaceBatch?

    init(
        assignedName: String = "",
        thumbnail: Data = Data(),
        exported: Bool = false,
        batch: FaceBatch? = nil,
        uuid: UUID = UUID(),
        order: Int = 0
    ) {
        self.uuid = uuid
        self.order = order
        self.assignedName = assignedName
        self.thumbnail = thumbnail
        self.exported = exported
        self.batch = batch
    }
}