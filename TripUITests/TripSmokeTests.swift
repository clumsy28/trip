import XCTest

final class TripSmokeTests: XCTestCase {
    func testLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
    }
}
