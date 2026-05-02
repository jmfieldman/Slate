import CoreData
import SlateSchema

@SlateEntity(
    relationships: [
        .toMany("notes", "PatientNote", inverse: "patient", deleteRule: .cascade, ordered: true),
    ]
)
public struct Patient {
    public let patientId: String
    public let firstName: String
    public let lastName: String
    public let age: Int?

    @SlateEmbedded
    public let address: Address?

    @SlateEmbedded
    public struct Address: Sendable, Hashable {
        public let line1: String?
        public let city: String?
        @SlateAttribute(storageName: "zip")
        public let postalCode: String?

        public init(line1: String?, city: String?, postalCode: String?) {
            self.line1 = line1
            self.city = city
            self.postalCode = postalCode
        }
    }

    public enum Status: String, Sendable {
        case active
        case archived
    }

    @SlateAttribute(default: Patient.Status.active)
    public let status: Status
}
