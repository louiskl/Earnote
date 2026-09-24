import SwiftData
import XCTest
@testable import EarnoteCore

/// CloudKit verlangt vom Datenmodell mehr als SwiftData allein: keine Pflichtfelder ohne Standardwert,
/// keine Eindeutigkeitsregeln, Beziehungen optional und mit Gegenstück. Verstößt ein neues Feld dagegen,
/// merkt man das sonst erst, wenn der Sync bei einem Nutzer nicht anläuft.
final class CloudKitSchemaTests: XCTestCase {
    private var entities: [Schema.Entity] {
        Schema(versionedSchema: EarnoteSchemaLatest.self).entities
    }

    func testEveryAttributeIsOptionalOrHasADefault() {
        for entity in entities {
            for attribute in entity.attributes {
                let name = "\(entity.name).\(attribute.name)"
                XCTAssertTrue(attribute.isOptional || attribute.defaultValue != nil,
                              "\(name) ist Pflicht ohne Standardwert – das kann CloudKit nicht")
                XCTAssertFalse(attribute.isUnique, "\(name) ist eindeutig – das kann CloudKit nicht")
            }
        }
    }

    func testEveryRelationshipIsOptionalWithAnInverseAndNoDenyRule() {
        for entity in entities {
            for relationship in entity.relationships {
                let name = "\(entity.name).\(relationship.name)"
                XCTAssertNotNil(relationship.inverseName, "\(name) hat kein Gegenstück")
                XCTAssertNotEqual(relationship.deleteRule, .deny, "\(name) verbietet das Löschen")
                XCTAssertTrue(relationship.isOptional || relationship.isToOneRelationship == false,
                              "\(name) ist eine Pflichtbeziehung")
            }
        }
    }

    /// Eine eigene id brauchen die Modelle, die die App selbst adressiert und die nach einem Sync
    /// doppelt auftauchen könnten. Transkript, Notiz und Export hängen dagegen an genau einer Aufnahme
    /// und werden nie einzeln gesucht – sie kommen mit der Aufnahme oder gar nicht.
    func testModelsTheAppAddressesCarryTheirOwnIdentifier() {
        let needsID = ["LibraryRecording", "LibraryCategory", "LibraryGlossaryTerm", "LibraryHandoff", "LibraryDevice"]
        for entity in entities where needsID.contains(entity.name) {
            XCTAssertTrue(entity.attributes.contains { $0.name == "id" },
                          "\(entity.name) hat keine eigene id – ohne sie lassen sich Duplikate nach dem Sync nicht erkennen")
        }
    }
}
