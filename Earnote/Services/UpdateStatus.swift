import EarnoteCore
import Foundation
import Observation

/// Prüft höchstens einmal am Tag, ob es eine neuere Version gibt, und hält das Ergebnis fest.
/// Installiert wird nichts automatisch: Die App zeigt einen Hinweis mit Link, der Rest ist Handarbeit.
@MainActor
@Observable
final class UpdateStatus {
    /// Neuere Version, falls es eine gibt
    private(set) var available: AppRelease?
    private(set) var isChecking = false
    /// Nach einer Prüfung ohne Ergebnis: „Du hast die neueste Version“
    private(set) var checkedAt: Date?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let currentVersion: String
    @ObservationIgnored private let lastCheckKey = "update.lastCheck"

    init(defaults: UserDefaults = .standard,
         currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0") {
        self.defaults = defaults
        self.currentVersion = currentVersion
    }

    /// Beim Start: nur prüfen, wenn die letzte Prüfung über einen Tag her ist.
    func checkIfDue() async {
        let last = defaults.object(forKey: lastCheckKey) as? Date
        guard last == nil || Date().timeIntervalSince(last!) > 24 * 3_600 else { return }
        await check()
    }

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false; checkedAt = Date() }
        defaults.set(Date(), forKey: lastCheckKey)
        do {
            let latest = try await UpdateCheck.latest(repository: AppInfo.repository)
            guard let latest, UpdateCheck.isNewer(latest.version, than: currentVersion) else {
                available = nil
                return
            }
            available = latest
            Log.info("Neue Version verfügbar: \(latest.version) (installiert: \(currentVersion))")
        } catch {
            Log.info("Update-Prüfung nicht möglich: \(error.localizedDescription)")
        }
    }
}
