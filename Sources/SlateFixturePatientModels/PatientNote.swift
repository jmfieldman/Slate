import CoreData
import SlateSchema

@SlateEntity(
    relationships: [
        .toOne("patient", "Patient", inverse: "notes", deleteRule: .nullify, optional: false),
    ]
)
public struct PatientNote {
    public let noteId: String
    public let body: String
}
