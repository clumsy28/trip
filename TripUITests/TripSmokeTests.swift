import XCTest

@MainActor
final class TripSmokeTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + extra
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Search a province, add a trip to it, and check the map's progress updates.
    func testAddTripPaintsProvince() {
        let app = launch()
        let progress = element(app, "map.progress")
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        XCTAssertTrue(progress.label.hasPrefix("0/81"), progress.label)

        element(app, "map.search").tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("izmir") // Turkish-aware matching: "izmir" finds "İzmir"
        let row = element(app, "region.TR-35")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let newTrip = element(app, "region.newTrip")
        XCTAssertTrue(newTrip.waitForExistence(timeout: 5))
        newTrip.tap()

        let save = element(app, "editor.save")
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // The trip shows up in the region sheet.
        XCTAssertTrue(app.staticTexts["İzmir · " + currentMonthYear()].waitForExistence(timeout: 5))

        app.swipeDown(velocity: .fast)
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        let painted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH '1/81'"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [painted], timeout: 5), .completed, progress.label)

        // The trips tab lists it too.
        app.tabBars.buttons["Geziler"].tap()
        XCTAssertTrue(app.staticTexts["İzmir · " + currentMonthYear()].waitForExistence(timeout: 5))
    }

    /// Requires geotagged photos in the simulator library (see Tools/make_test_photos.swift) and photo access.
    func testAutoImportSuggestsTripsFromPhotos() throws {
        addUIInterruptionMonitor(withDescription: "Photos permission") { alert in
            for label in ["Allow Full Access", "Tam Erişime İzin Ver", "Allow Access to All Photos"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        let app = launch(["-autoImport"])
        app.tap() // lets the interruption monitor run if an alert is up

        let apply = element(app, "autoImport.apply")
        let none = app.staticTexts["Yeni gezi bulunamadı"]
        let appeared = apply.waitForExistence(timeout: 30) || none.exists
        XCTAssertTrue(appeared, "Scan did not finish")
        if !apply.exists {
            throw XCTSkip("No geotagged test photos in this simulator's library")
        }

        XCTAssertTrue(app.staticTexts["İzmir, Türkiye"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Fransa"].firstMatch.exists)
        apply.tap()

        let showOnMap = app.buttons["Haritada gör"]
        XCTAssertTrue(showOnMap.waitForExistence(timeout: 10))
        showOnMap.tap()

        let progress = element(app, "map.progress")
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertFalse(progress.label.hasPrefix("0/81"), progress.label)
        sleep(1)
        attachScreenshot(app, "map-after-import")

        app.tabBars.buttons["Geziler"].tap()
        let izmir = app.staticTexts["İzmir · Ağustos 2025"]
        XCTAssertTrue(izmir.waitForExistence(timeout: 5))
        attachScreenshot(app, "trips-after-import")
        izmir.tap()
        sleep(2) // let thumbnails load
        attachScreenshot(app, "trip-detail-after-import")
    }

    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func currentMonthYear() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.setLocalizedDateFormatFromTemplate("MMMMy")
        return f.string(from: .now)
    }
}
