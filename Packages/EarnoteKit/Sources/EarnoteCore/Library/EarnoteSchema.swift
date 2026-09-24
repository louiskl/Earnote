import Foundation
import SwiftData

// Datenmodell der Bibliothek. Von Anfang an so gebaut, dass es später ohne Umbau über iCloud (CloudKit)
// synchronisiert werden kann. Regeln für jedes Modell:
// - jedes Attribut optional oder mit Standardwert
// - keine eindeutigen Attribute (`.unique` / `#Unique`)
// - jede Beziehung optional, mit expliziter Inverse, keine `.deny`-Löschregel
// - Enums als String-Rohwert, große Daten mit `.externalStorage`
// - eigene stabile `id: UUID` als normales Attribut bei allem, was die App selbst adressiert
//   (Aufnahme, Bereich, Wörterbucheintrag). Transkript, Notiz und Export hängen an genau einer
//   Aufnahme und werden nie einzeln gesucht – sie brauchen keine.
// Audiodateien gehören nicht dazu; sie bleiben lokal (`AudioStore`).

public enum EarnoteSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [LibraryRecording.self, LibraryTranscript.self, LibraryNote.self, LibraryCategory.self,
         LibraryGlossaryTerm.self, LibraryExport.self]
    }
}

/// V2 (Weg B, docs/IPHONE.md Abschnitt 6a): Übergabe von Aufnahmen vom iPhone an den Mac und die Geräte der Bibliothek.
/// Nur neue Modelle – die aus V1 bleiben unverändert, deshalb reicht eine leichte Migration.
/// Vor dem ersten Abgleich mit V2 das CloudKit-Schema neu anlegen (ROADMAP, „iCloud-Sync“, Schritt 5).
public enum EarnoteSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)

    public static var models: [any PersistentModel.Type] {
        EarnoteSchemaV1.models + [LibraryHandoff.self, LibraryDevice.self]
    }
}

/// Das Schema, mit dem die Bibliothek geöffnet wird
public typealias EarnoteSchemaLatest = EarnoteSchemaV2

public enum EarnoteMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [EarnoteSchemaV1.self, EarnoteSchemaV2.self] }
    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: EarnoteSchemaV1.self, toVersion: EarnoteSchemaV2.self)]
    }
}

public typealias LibraryRecording = EarnoteSchemaV1.LibraryRecording
public typealias LibraryTranscript = EarnoteSchemaV1.LibraryTranscript
public typealias LibraryNote = EarnoteSchemaV1.LibraryNote
public typealias LibraryCategory = EarnoteSchemaV1.LibraryCategory
public typealias LibraryGlossaryTerm = EarnoteSchemaV1.LibraryGlossaryTerm
public typealias LibraryExport = EarnoteSchemaV1.LibraryExport
public typealias LibraryHandoff = EarnoteSchemaV2.LibraryHandoff
public typealias LibraryDevice = EarnoteSchemaV2.LibraryDevice

extension EarnoteSchemaV1 {
    /// Eine Aufnahme. Der Verarbeitungsfortschritt wird bewusst nicht gespeichert.
    @Model
    public final class LibraryRecording {
        public var id: UUID = UUID()
        public var title: String = ""
        /// Vom Nutzer benannt (sonst automatischer Name wie „Meeting – 15. Sept., 19:58“)
        public var isTitleCustom: Bool = false
        public var startedAt: Date = Date()
        public var endedAt: Date?
        /// Summe der Pausen in Sekunden
        public var pausedDuration: Double = 0
        public var sourceApp: String?
        public var languageCode: String = "de"
        /// `RecordingOrigin`
        public var originRaw: String = RecordingOrigin.microphone.rawValue
        public var hasSystemAudio: Bool = false
        public var importedFileName: String?
        /// `RecordingStatus`
        public var statusRaw: String = RecordingStatus.queued.rawValue
        public var errorMessage: String?
        public var createdAt: Date = Date()
        public var modifiedAt: Date = Date()

        /// Wird ein Bereich gelöscht, bleibt die Aufnahme ohne Bereich erhalten (Inverse: `LibraryCategory.recordings`, nullify)
        public var category: LibraryCategory?
        @Relationship(deleteRule: .cascade, inverse: \LibraryTranscript.recording)
        public var transcript: LibraryTranscript?
        @Relationship(deleteRule: .cascade, inverse: \LibraryNote.recording)
        public var note: LibraryNote?
        @Relationship(deleteRule: .cascade, inverse: \LibraryExport.recording)
        public var exports: [LibraryExport]? = []

        public init(id: UUID = UUID()) {
            self.id = id
        }

        public var status: RecordingStatus {
            get { RecordingStatus(rawValue: statusRaw) ?? .queued }
            set { statusRaw = newValue.rawValue }
        }

        public var origin: RecordingOrigin {
            get { RecordingOrigin(rawValue: originRaw) ?? .microphone }
            set { originRaw = newValue.rawValue }
        }
    }

    /// Transkript einer Aufnahme: alle Segmente als ein Datenblock, dazu reiner Text für die Suche.
    @Model
    public final class LibraryTranscript {
        public var engine: String = ""
        /// JSON von `[TranscriptSegment]`
        @Attribute(.externalStorage)
        public var segmentsData: Data?
        public var plainText: String = ""
        public var wordCount: Int = 0
        public var createdAt: Date = Date()
        public var recording: LibraryRecording?

        public init() {}
    }

    /// Notiz einer Aufnahme: aktuelle (bearbeitbare) Fassung und das Original der KI.
    @Model
    public final class LibraryNote {
        public var title: String = ""
        public var markdown: String = ""
        public var generatedTitle: String = ""
        public var generatedMarkdown: String = ""
        public var provider: String = ""
        public var modelName: String?
        public var taskCount: Int = 0
        public var preview: String?
        public var createdAt: Date = Date()
        public var editedAt: Date?
        public var recording: LibraryRecording?

        public init() {}
    }

    /// Ein Bereich (Kategorie) mit eigenen Anweisungen für die KI.
    @Model
    public final class LibraryCategory {
        public var id: UUID = UUID()
        public var name: String = ""
        public var emoji: String?
        public var symbol: String = "star.fill"
        public var colorHex: String = "#4F7CFF"
        public var instructions: String = ""
        /// Leer = alle aktivierten Ziele
        public var destinationIDs: [String] = []
        public var sortIndex: Int = 0
        public var createdAt: Date = Date()

        @Relationship(deleteRule: .nullify, inverse: \LibraryRecording.category)
        public var recordings: [LibraryRecording]? = []
        @Relationship(deleteRule: .cascade, inverse: \LibraryGlossaryTerm.category)
        public var glossary: [LibraryGlossaryTerm]? = []

        public init(id: UUID = UUID()) {
            self.id = id
        }
    }

    /// Wörterbuch-Eintrag: richtige Schreibweise eines Begriffs und typische Hörfehler.
    @Model
    public final class LibraryGlossaryTerm {
        public var id: UUID = UUID()
        public var term: String = ""
        public var variants: [String] = []
        public var note: String?
        /// nil = gilt in allen Bereichen
        public var category: LibraryCategory?

        public init(id: UUID = UUID()) {
            self.id = id
        }
    }

    /// Ergebnis eines Exports in ein Ziel.
    @Model
    public final class LibraryExport {
        public var destinationID: String = ""
        public var destinationName: String = ""
        /// `ExportState`
        public var stateRaw: String = ExportState.success.rawValue
        public var message: String = ""
        public var externalURL: String?
        public var date: Date = Date()
        public var recording: LibraryRecording?

        public init() {}

        public var state: ExportState {
            get { ExportState(rawValue: stateRaw) ?? .failed }
            set { stateRaw = newValue.rawValue }
        }
    }
}

extension EarnoteSchemaV2 {
    /// Eine Aufnahme auf dem Weg vom iPhone zum Mac. Das Audio liegt nur so lange in iCloud, bis der Mac
    /// sie verarbeitet hat – dann löscht er dieses Objekt. Keine Beziehung zur Aufnahme, nur ihre ID:
    /// So braucht es keine Inverse, und die Aufnahme bleibt unberührt, wenn die Übergabe verschwindet.
    @Model
    public final class LibraryHandoff {
        public var id: UUID = UUID()
        public var recordingID: UUID?
        public var createdAt: Date = Date()
        /// Name des Geräts, das aufgenommen hat (für Hinweise wie „vom iPhone von …“)
        public var fromDevice: String = ""
        @Attribute(.externalStorage)
        public var audio: Data?
        /// Dateiendung des Audios
        public var audioFormat: String = "m4a"
        /// `HandoffState`
        public var stateRaw: String = HandoffState.waiting.rawValue
        /// `SyncedDevice.id` des Macs, der die Aufnahme verarbeitet
        public var claimedBy: UUID?
        public var claimedAt: Date?
        public var errorMessage: String?

        public init(id: UUID = UUID()) {
            self.id = id
        }

        public var state: HandoffState {
            get { HandoffState(rawValue: stateRaw) ?? .waiting }
            set { stateRaw = newValue.rawValue }
        }
    }

    /// Ein Gerät mit dieser Bibliothek. Das iPhone erkennt daran, ob ein Mac Aufnahmen übernehmen kann.
    @Model
    public final class LibraryDevice {
        public var id: UUID = UUID()
        public var name: String = ""
        /// `DevicePlatform`
        public var platformRaw: String = DevicePlatform.mac.rawValue
        /// Übernimmt Aufnahmen anderer Geräte (Weg B)
        public var canProcess: Bool = false
        /// Höchste Schema-Version, die das Gerät kennt
        public var schemaVersion: Int = 2
        public var lastSeen: Date = Date()

        public init(id: UUID = UUID()) {
            self.id = id
        }

        public var platform: DevicePlatform {
            get { DevicePlatform(rawValue: platformRaw) ?? .mac }
            set { platformRaw = newValue.rawValue }
        }
    }
}

public enum ExportState: String, Codable, Sendable {
    case success, skipped, failed
}
