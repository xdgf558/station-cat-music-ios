import XCTest

// Explicit local R2 acceptance only. XCUISystem opens through the OS default
// handler; this test never calls AppModel, onOpenURL, or target-app open(URL).
@MainActor final class R2UniversalLinkUITests: XCTestCase {
    private let origin = "https://station-cat-music-r2.yehao1105.workers.dev"
    private let bundleID = "org.stationcat.music.staging"
    private var phase = "input"

    private struct Input: Decodable {
        struct Tracks: Decodable { let free: String; let vip: String }
        let origin: String
        let tracks: Tracks
        let collectionSlug: String
    }
    private enum Failure: Error { case input, assertion }
    private func require(_ value: Bool) throws { if !value { throw Failure.assertion } }
    private func evidence(_ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "R2-system-link-" + phase
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func observeIdle(_ app: XCUIApplication) throws {
        let paused = app.buttons.matching(NSPredicate(format: "label IN %@", ["Pause", "暂停", "暫停", "一時停止"])).firstMatch
        let playing = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["Playing", "正在播放", "再生中"])).firstMatch
        let checks = [paused, playing].map { element in
            let check = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: element)
            check.isInverted = true
            return check
        }
        try require(XCTWaiter.wait(for: checks, timeout: 3) == .completed)
    }

    private func input() throws -> Input {
        guard let path = ProcessInfo.processInfo.environment["R2_PRIVATE_INPUT"], path.hasPrefix("/") else { throw Failure.input }
        let url = URL(fileURLWithPath: path)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
              ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 8192,
              try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw Failure.input }
        let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: url))
        guard input.origin == origin, input.collectionSlug == "r2-synthetic-album",
              UUID(uuidString: input.tracks.free) != nil, UUID(uuidString: input.tracks.vip) != nil,
              input.tracks.free != input.tracks.vip else { throw Failure.input }
        return input
    }

    private func dispatch(_ url: URL, to app: XCUIApplication, cold: Bool) throws {
        if cold {
            app.terminate()
            try require(app.wait(for: .notRunning, timeout: 10))
        } else {
            XCUIDevice.shared.press(.home)
            let background = XCTNSPredicateExpectation(predicate: NSPredicate(format: "state == %d OR state == %d",
                Int(XCUIApplication.State.runningBackground.rawValue), Int(XCUIApplication.State.runningBackgroundSuspended.rawValue)), object: app)
            try require(XCTWaiter.wait(for: [background], timeout: 5) == .completed)
        }
        XCUIDevice.shared.system.open(url)
        try require(app.wait(for: .runningForeground, timeout: 20))
    }

    func testSystemDispatchesColdAndWarmAlbumAndTrackLinks() throws {
        guard ProcessInfo.processInfo.environment["R2_ENABLE_SYSTEM_UI"] == "YES" else {
            throw XCTSkip("Explicit isolated R2 system UI acceptance only")
        }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: bundleID)
        defer { app.terminate() }
        do {
            let value = try input()
            app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            phase = "staging_ready"
            app.launch()
            try require(app.buttons["track." + value.tracks.free].waitForExistence(timeout: 20))
            var trackLink = URLComponents(string: origin + "/music/")!
            trackLink.queryItems = [.init(name: "track", value: value.tracks.free)]
            var albumLink = URLComponents(string: origin + "/music/")!
            albumLink.queryItems = [.init(name: "collection", value: value.collectionSlug)]
            for cold in [false, true] {
                phase = cold ? "cold_track" : "warm_track"
                try dispatch(trackLink.url!, to: app, cold: cold)
                // The unique synthetic lyric establishes that the requested track
                // reached the player, independently of the simulator UI language.
                try require(app.staticTexts["R2 isolated synthetic audio"].waitForExistence(timeout: 20))
                let play = app.buttons.matching(NSPredicate(format: "label IN %@", ["Play", "播放", "再生"])).firstMatch
                try require(play.exists)
                try observeIdle(app)
                evidence(app)
                print("R2_SYSTEM_LINK_STEP:\(phase):passed")
                let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Close", "关闭", "關閉", "閉じる"])).firstMatch
                try require(close.exists); close.tap()

                phase = cold ? "cold_album" : "warm_album"
                try dispatch(albumLink.url!, to: app, cold: cold)
                let catalog = app.scrollViews["catalogScreen"]
                try require(catalog.waitForExistence(timeout: 20))
                let album = catalog.buttons.matching(NSPredicate(format: "label IN %@", ["R2 Synthetic Test Album", "R2 合成测试专辑", "R2 合成測試專輯", "R2 合成テストアルバム"])).firstMatch
                try require(album.waitForExistence(timeout: 20))
                try require(catalog.buttons["track." + value.tracks.free].exists)
                try require(catalog.buttons["track." + value.tracks.vip].exists)
                try observeIdle(app)
                evidence(app)
                print("R2_SYSTEM_LINK_STEP:\(phase):passed")
            }
            print("R2_SYSTEM_LINKS_PASSED: os_default_dispatch=true warm_track=true cold_track=true warm_album=true cold_album=true idle_observation_seconds_per_link=3 physical_device=false")
        } catch {
            // Do not print URLs, response bodies, input data or UI-tree snapshots.
            XCTFail("R2_SYSTEM_LINKS_FAILED phase=\(phase) category=assertion")
        }
    }
}
