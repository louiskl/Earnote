import EarnoteCore
import AppKit
import CoreAudio
import Foundation

/// Erkennt laufende Calls: prüft, welche Apps gerade das Mikrofon verwenden
/// (Core Audio Prozessliste, macOS 14.2+). Keine zusätzlichen Berechtigungen nötig.
@MainActor
final class MeetingDetector: ObservableObject {
    @Published private(set) var activeCallApp: String?

    var onCallStarted: ((String) -> Void)?
    var onCallEnded: ((String) -> Void)?

    private var timer: Timer?
    private var endCandidateSince: Date?
    private let endGrace: TimeInterval = 10
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    nonisolated static let knownApps: [(prefix: String, name: String)] = [
        ("us.zoom", "Zoom"),
        ("com.microsoft.teams", "Microsoft Teams"),
        ("com.cisco.webex", "Webex"),
        ("Cisco-Systems.Spark", "Webex"),
        ("com.apple.FaceTime", "FaceTime"),
        ("com.apple.TelephonyUtilities", "FaceTime"),
        ("com.tinyspeck.slackmacgap", "Slack"),
        ("com.hnc.Discord", "Discord"),
        ("net.whatsapp.WhatsApp", "WhatsApp"),
        ("desktop.WhatsApp", "WhatsApp"),
        ("ru.keepcoder.Telegram", "Telegram"),
        ("com.skype.skype", "Skype"),
        ("com.gotomeeting", "GoTo Meeting"),
        ("com.logmein.GoToMeeting", "GoTo Meeting"),
        ("com.ringcentral", "RingCentral"),
        ("com.bigbluebutton", "BigBlueButton"),
        ("de.alfaview", "alfaview"),
        ("com.google.Chrome", "Browser-Call (z. B. Google Meet)"),
        ("com.apple.WebKit", "Browser-Call (Safari)"),
        ("com.apple.Safari", "Browser-Call (Safari)"),
        ("company.thebrowser", "Browser-Call (Arc)"),
        ("org.mozilla.firefox", "Browser-Call (Firefox)"),
        ("com.microsoft.edgemac", "Browser-Call (Edge)"),
        ("com.brave.Browser", "Browser-Call (Brave)"),
        ("com.vivaldi.Vivaldi", "Browser-Call (Vivaldi)"),
    ]

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        activeCallApp = nil
    }

    private func scan() {
        let found = Self.appsUsingMicrophone(excluding: ownPID).first
        if let found {
            endCandidateSince = nil
            if activeCallApp != found {
                let isNew = activeCallApp == nil
                activeCallApp = found
                if isNew { onCallStarted?(found) }
            }
        } else if let current = activeCallApp {
            if endCandidateSince == nil { endCandidateSince = Date() }
            if let since = endCandidateSince, Date().timeIntervalSince(since) >= endGrace {
                activeCallApp = nil
                endCandidateSince = nil
                onCallEnded?(current)
            }
        }
    }

    nonisolated static func appsUsingMicrophone(excluding pid: pid_t) -> [String] {
        var names: [String] = []
        for process in AudioObjectID.systemObject.readIDs(kAudioHardwarePropertyProcessObjectList) {
            let running = (try? process.read(kAudioProcessPropertyIsRunningInput, default: UInt32(0))) ?? 0
            guard running != 0 else { continue }
            let processPID = (try? process.read(kAudioProcessPropertyPID, default: pid_t(0))) ?? 0
            if processPID == pid { continue }
            guard let bundle = process.readString(kAudioProcessPropertyBundleID), !bundle.isEmpty else { continue }
            // Eigene App (auch unter dem früheren Namen) nicht als Call werten
            if bundle.hasPrefix(AppInfo.bundleIdentifier) || bundle.hasPrefix(AppInfo.legacyBundleIdentifier) { continue }
            if let match = knownApps.first(where: { bundle.hasPrefix($0.prefix) }) {
                names.append(match.name)
            }
        }
        // Echte Call-Apps vor Browsern bevorzugen
        return names.sorted { !$0.hasPrefix("Browser") && $1.hasPrefix("Browser") }
    }
}
