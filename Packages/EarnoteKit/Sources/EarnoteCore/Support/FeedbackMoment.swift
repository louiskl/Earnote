import Foundation

/// Was Earnote am iPhone/iPad von sich aus zeigt: „Neu in Earnote“, die Bitte um eine Bewertung, das Dankeschön-Paket.
/// Höchstens eins auf einmal; ob gerade aufgenommen wird oder ein Blatt offen ist, prüft der Aufrufer.
public enum FeedbackMoment: Equatable, Sendable {
    case whatsNew, review, supporter

    /// Bewertung erst, wenn Earnote ein paar Notizen geschrieben hat – dann weiß man, ob die App taugt
    public static let reviewAfterNotes = 3
    public static let supporterAfterNotes = 5
    /// Das Dankeschön-Paket kommt wieder, aber nicht öfter als einmal im Monat
    public static let supporterPause: TimeInterval = 30 * 24 * 3600

    /// - Parameters:
    ///   - whatsNewVersion: Version, zu der es „Neu in Earnote“ gibt (nil = keine)
    ///   - lastSeenVersion: zuletzt gesehenes „Neu in Earnote“ (neue Nutzer bekommen es nach dem Onboarding gesetzt)
    ///   - reviewAskedVersion: Version, in der zuletzt um eine Bewertung gebeten wurde – höchstens einmal je Version
    public static func next(version: String, whatsNewVersion: String?, finishedNotes: Int, isSupporter: Bool,
                            lastSeenVersion: String?, reviewAskedVersion: String?, supporterAskedAt: Date?,
                            now: Date = .now) -> FeedbackMoment? {
        if whatsNewVersion == version && lastSeenVersion != version { return .whatsNew }
        if finishedNotes >= reviewAfterNotes && reviewAskedVersion != version { return .review }
        if !isSupporter && finishedNotes >= supporterAfterNotes,
           supporterAskedAt.map({ now.timeIntervalSince($0) >= supporterPause }) ?? true {
            return .supporter
        }
        return nil
    }
}
