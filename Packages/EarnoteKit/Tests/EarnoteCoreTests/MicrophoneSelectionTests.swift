import XCTest
@testable import EarnoteCore

final class MicrophoneSelectionTests: XCTestCase {
    // Geräte wie auf dem Mac, auf dem Fehler 35 auftrat
    private let usb = AudioInputDeviceInfo(uid: "AppleUSBAudioEngine:C310 HD WebCam:C310 HD WebCam:1140000:3", name: "USB Microphone",
                                           transport: .usb, channels: 2)
    private let builtIn = AudioInputDeviceInfo(uid: "BuiltInMicrophoneDevice", name: "MacBook Air-Mikrofon", transport: .builtIn)
    private let headset = AudioInputDeviceInfo(uid: "00-11-22-33-44-55:input", name: "G435 Wireless Gaming Headset", transport: .bluetooth)
    private let iPhone = AudioInputDeviceInfo(uid: "7FA5E810-D409-45D8-A01D-A6D100000003", name: "Mikrofon von „louis“", transport: .continuity)
    private let blackHole = AudioInputDeviceInfo(uid: "BlackHole2ch_UID", name: "BlackHole 2ch", transport: .virtual, channels: 2)
    private let teams = AudioInputDeviceInfo(uid: "MSLoopbackDriverDevice_UID", name: "Microsoft Teams Audio", transport: .unknown)
    private let ownAggregate = AudioInputDeviceInfo(uid: "app.earnote.Earnote.aggregate.1234", name: "Earnote Systemaudio", transport: .unknown)
    private var all: [AudioInputDeviceInfo] { [blackHole, usb, teams, headset, iPhone, builtIn, ownAggregate] }

    func testVirtualDevicesAreRecognized() {
        XCTAssertTrue(blackHole.isVirtual)
        XCTAssertTrue(teams.isVirtual, "Teams-Treiber meldet keinen virtuellen Transport, wird am Namen erkannt")
        XCTAssertTrue(ownAggregate.isVirtual)
        XCTAssertTrue(AudioInputDeviceInfo(uid: "x", name: "Aggregat", transport: .aggregate).isVirtual)
        for real in [usb, builtIn, headset, iPhone] { XCTAssertFalse(real.isVirtual, real.name) }
    }

    func testSystemHelperAggregatesAreHidden() {
        let helper = AudioInputDeviceInfo(uid: "CADefaultDeviceAggregate-57354-0", name: "CADefaultDeviceAggregate-57354-0", transport: .unknown)
        XCTAssertTrue(helper.isSystemHelper)
        XCTAssertFalse(MicrophonePlan.sortedForDisplay(all + [helper]).contains(helper))
        XCTAssertFalse(MicrophonePlan.start(devices: all + [helper], preferredUID: nil, defaultUID: nil).candidates.contains(helper))
    }

    func testDisplayOrderPutsRealDevicesFirst() {
        let names = MicrophonePlan.sortedForDisplay(all).map(\.name)
        XCTAssertEqual(names.first, "MacBook Air-Mikrofon")
        XCTAssertEqual(Set(names.suffix(3)), ["BlackHole 2ch", "Microsoft Teams Audio", "Earnote Systemaudio"])
    }

    func testSystemDefaultThenBuiltInThenOtherRealDevices() {
        let plan = MicrophonePlan.start(devices: all, preferredUID: nil, defaultUID: usb.uid)
        XCTAssertEqual(plan.candidates.map(\.name), ["USB Microphone", "MacBook Air-Mikrofon", "Mikrofon von „louis“", "G435 Wireless Gaming Headset"])
        XCTAssertFalse(plan.preferredMissing)
        XCTAssertFalse(plan.candidates.dropFirst().contains { $0.isVirtual }, "Nie automatisch auf virtuelle Geräte ausweichen")
    }

    func testChosenDeviceComesFirstEvenIfVirtual() {
        let plan = MicrophonePlan.start(devices: all, preferredUID: blackHole.uid, defaultUID: usb.uid)
        XCTAssertEqual(plan.candidates.first, blackHole)
        XCTAssertEqual(plan.candidates.dropFirst().first, builtIn)
        XCTAssertFalse(plan.candidates.contains(teams))
    }

    func testMissingChosenDeviceUsesSystemDefault() {
        let plan = MicrophonePlan.start(devices: all, preferredUID: "gone", defaultUID: builtIn.uid)
        XCTAssertTrue(plan.preferredMissing)
        XCTAssertEqual(plan.candidates.first, builtIn)
        XCTAssertEqual(Set(plan.candidates.map(\.uid)).count, plan.candidates.count, "Kein Gerät doppelt")
    }

    func testVirtualSystemDefaultWithoutRealDevices() {
        let plan = MicrophonePlan.start(devices: [blackHole], preferredUID: nil, defaultUID: blackHole.uid)
        XCTAssertEqual(plan.candidates, [blackHole])
        XCTAssertTrue(MicrophonePlan.start(devices: [], preferredUID: nil, defaultUID: nil).candidates.isEmpty)
        XCTAssertEqual(MicrophonePlan.start(devices: [blackHole, usb], preferredUID: nil, defaultUID: nil).candidates.first, usb,
                       "Ohne Standardgerät ein echtes Mikrofon nehmen")
    }

    func testReplacementDuringRecording() {
        XCTAssertEqual(MicrophonePlan.replacement(devices: all.filter { $0 != usb }, lostUID: usb.uid, preferredUID: usb.uid,
                                                  defaultUID: iPhone.uid).map(\.name),
                       ["Mikrofon von „louis“", "MacBook Air-Mikrofon", "G435 Wireless Gaming Headset"])
        XCTAssertEqual(MicrophonePlan.replacement(devices: [usb, blackHole], lostUID: usb.uid, preferredUID: nil, defaultUID: usb.uid), [],
                       "Weder das verlorene noch virtuelle Geräte als Ersatz")
    }

    func testMessagesAreGermanWithoutErrorCodes() {
        let events: [MicrophoneEvent] = [.permissionDenied, .noDevices, .allFailed,
                                         .preferredMissing(preferred: "Headset", used: "MacBook Air-Mikrofon"),
                                         .fellBack(failed: "USB Microphone", used: "MacBook Air-Mikrofon"),
                                         .switchedDuringRecording(lost: "USB Microphone", used: "MacBook Air-Mikrofon"),
                                         .lostWithoutReplacement(lost: "USB Microphone")]
        for event in events {
            XCTAssertNil(event.message.range(of: #"\d{2,}|Fehler|error|avfaudio|OSStatus"#, options: [.regularExpression, .caseInsensitive]),
                         event.message)
        }
        XCTAssertEqual(MicrophoneEvent.fellBack(failed: "USB Microphone", used: "MacBook Air-Mikrofon").message,
                       "Das Mikrofon „USB Microphone“ hat nicht reagiert. Die Aufnahme läuft über „MacBook Air-Mikrofon“.")
        XCTAssertTrue(MicrophoneEvent.allFailed.message.contains("Einstellungen unter „Aufnahme“"))
    }

    func testMicrophoneSettingDecoding() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"language":"de","keepAudioFiles":true}"#.utf8))
        XCTAssertNil(old.microphoneDeviceUID, "Ältere Einstellungen: Systemstandard")
        XCTAssertNil(old.microphoneDeviceName)

        let broken = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"microphoneDeviceUID":42,"language":"en"}"#.utf8))
        XCTAssertNil(broken.microphoneDeviceUID)
        XCTAssertEqual(broken.language, "en", "Ein kaputtes Feld setzt nicht alles zurück")

        var settings = AppSettings()
        settings.microphoneDeviceUID = usb.uid
        settings.microphoneDeviceName = usb.name
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.microphoneDeviceUID, usb.uid)
        XCTAssertEqual(decoded.microphoneDeviceName, "USB Microphone")
    }
}
