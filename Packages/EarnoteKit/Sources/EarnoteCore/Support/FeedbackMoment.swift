import Foundation

/// Was Earnote am iPhone/iPad von sich aus zeigt: „Neu in Earnote“, die Bitte um eine Bewertung, das Dankeschön-Paket.
/// Höchstens eins auf einmal; ob gerade aufgenommen wird oder ein Blatt offen ist, prüft der Aufrufer.
/// Beim Start der App höchstens „Neu in Earnote“ – dann will man meist schnell aufnehmen. Bewertung und Dankeschön-Paket
/// erst im Erfolgsmoment: wenn eine fertige Notiz offen ist.
public enum FeedbackMoment: Equatable, Sendable {
    case whatsNew, review, supporter

    /// Bewertung erst, wenn Earnote ein paar Notizen geschrieben hat – dann weiß man, ob die App taugt
    public static let reviewAfterNotes = 3
    public static let supporterAfterNotes = 5
    /// Das Dankeschön-Paket kommt wieder, aber nicht öfter als einmal im Monat …
    public static let supporterPause: TimeInterval = 30 * 24 * 3600
    /// … und nach drei Mal gar nicht mehr
    public static let supporterMaxAsks = 3

    /// - Parameters:
    ///   - afterSuccess: Eine fertige Notiz ist gerade offen (sonst: Start der App)
    ///   - whatsNewVersion: Version, zu der es „Neu in Earnote“ gibt (nil = keine)
    ///   - lastSeenVersion: zuletzt gesehenes „Neu in Earnote“ (neue Nutzer bekommen es nach dem Onboarding gesetzt)
    ///   - reviewAskedVersion: Version, in der zuletzt um eine Bewertung gebeten wurde – höchstens einmal je Version
    ///   - supporterAsks: wie oft das Dankeschön-Paket schon kam; `supporterDeclined`: „Nicht mehr fragen“ gewählt
    public static func next(afterSuccess: Bool, version: String, whatsNewVersion: String?, finishedNotes: Int,
                            isSupporter: Bool, lastSeenVersion: String?, reviewAskedVersion: String?,
                            supporterAskedAt: Date?, supporterAsks: Int = 0, supporterDeclined: Bool = false,
                            now: Date = .now) -> FeedbackMoment? {
        guard afterSuccess else {
            return whatsNewVersion == version && lastSeenVersion != version ? .whatsNew : nil
        }
        if finishedNotes >= reviewAfterNotes && reviewAskedVersion != version { return .review }
        if !isSupporter, !supporterDeclined, supporterAsks < supporterMaxAsks, finishedNotes >= supporterAfterNotes,
           supporterAskedAt.map({ now.timeIntervalSince($0) >= supporterPause }) ?? true {
            return .supporter
        }
        return nil
    }
}
