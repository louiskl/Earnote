#if DEBUG
import CloudKit
import CoreData
import EarnoteCore
import SwiftData

/// Legt das CloudKit-Schema vollständig an – einmalig, nur im Debug-Build.
///
/// Warum es das braucht: Ohne diesen Schritt entsteht das Schema in der Development-Umgebung
/// nebenbei, während echte Datensätze hochgeladen werden. Felder, die dabei nirgends einen Wert
/// hatten (etwa `editedAt` einer nie bearbeiteten Notiz), fehlen dann. Wird ein solches Schema nach
/// Production übernommen, lehnt CloudKit später jeden Export ab:
/// „Cannot create or modify field 'CD_editedAt' in record 'CD_LibraryNote' in production schema“.
///
/// `initializeCloudKitSchema` legt dagegen jeden Typ mit jedem Feld an.
///
/// Ablauf (einmalig, wenn sich das Datenmodell ändert):
/// 1. Projekt mit Development-Berechtigung erzeugen:
///    `EARNOTE_ICLOUD_DEV_TEAM=<TeamID> python3 scripts/generate_xcodeproj.py`
/// 2. In Xcode mit gesetzter Umgebungsvariable `EARNOTE_INIT_CLOUD_SCHEMA=1` starten (⌘R).
///    Die App schreibt das Ergebnis ins Protokoll und beendet sich.
/// 3. In der CloudKit Console: Development → Production übernehmen („Deploy Schema Changes“).
enum CloudSchemaSetup {
    static var isRequested: Bool { ProcessInfo.processInfo.environment["EARNOTE_INIT_CLOUD_SCHEMA"] == "1" }

    /// Legt alle Record-Typen und Felder in der Development-Umgebung an. Gibt zurück, ob es geklappt hat.
    static func run() -> Bool {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: EarnoteSchemaV1.models) else {
            Log.error("CloudKit-Schema: Datenmodell ließ sich nicht erzeugen")
            return false
        }
        let container = NSPersistentCloudKitContainer(name: "EarnoteSchema", managedObjectModel: model)
        // Eigener, leerer Speicher: Die Bibliothek des Nutzers wird dabei nicht angefasst.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EarnoteSchema-\(UUID().uuidString).sqlite")
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions =
            NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.\(AppInfo.bundleIdentifier)")
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            Log.error("CloudKit-Schema: Speicher öffnen: \(loadError)")
            return false
        }
        do {
            try container.initializeCloudKitSchema(options: [])
            Log.info("CloudKit-Schema in Development angelegt – jetzt in der CloudKit Console nach Production übernehmen")
            return true
        } catch {
            Log.error("CloudKit-Schema anlegen: \(error)")
            return false
        }
    }
}
#endif
