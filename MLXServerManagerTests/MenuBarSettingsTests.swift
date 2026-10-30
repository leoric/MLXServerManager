import XCTest
@testable import MLXServerManager

/// The two menu bar settings: whether the icon is shown, and what happens when the last
/// window closes.
@MainActor
final class MenuBarSettingsTests: XCTestCase {
    func testDefaults() {
        XCTAssertTrue(AppSettings.defaults.showMenuBarIcon, "the icon is shown by default")
        XCTAssertFalse(
            AppSettings.defaults.backgroundOnLastWindowClose,
            "closing the window keeps the app in the Dock by default"
        )
    }

    func testSettingsSavedBeforeTheOptionsExistGetDefaults() throws {
        let data = try JSONEncoder().encode(AppSettings.defaults)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["showMenuBarIcon"], "sanity: current settings encode the new keys")
        object.removeValue(forKey: "showMenuBarIcon")
        object.removeValue(forKey: "backgroundOnLastWindowClose")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacy)

        XCTAssertTrue(decoded.showMenuBarIcon)
        XCTAssertFalse(decoded.backgroundOnLastWindowClose)
    }

    func testSettingsRoundTrip() throws {
        var settings = AppSettings.defaults
        settings.showMenuBarIcon = false
        settings.backgroundOnLastWindowClose = true

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        XCTAssertFalse(decoded.showMenuBarIcon)
        XCTAssertTrue(decoded.backgroundOnLastWindowClose)
    }

    func testLastWindowCloseAction() {
        func action(background: Bool, icon: Bool) -> LastWindowCloseAction {
            LastWindowCloseAction.resolve(backgroundOnLastWindowClose: background, showMenuBarIcon: icon)
        }

        XCTAssertEqual(action(background: false, icon: true), .keepInDock)
        XCTAssertEqual(action(background: false, icon: false), .keepInDock)
        XCTAssertEqual(action(background: true, icon: true), .hideDockIcon)
        XCTAssertEqual(action(background: true, icon: false), .quit)
    }
}
