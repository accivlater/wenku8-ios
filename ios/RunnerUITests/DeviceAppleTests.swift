import XCTest

@MainActor
final class DeviceAppleTests: XCTestCase {
  func testSpotlightOpensIndexedBook() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "com.zhujinyu.wenku8flutter")
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), app.debugDescription)
    sleep(3)
    XCUIDevice.shared.press(.home)
    sleep(1)
    XCUIDevice.shared.press(.home)
    sleep(1)

    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let start = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
    let end = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
    start.press(forDuration: 0.1, thenDragTo: end)
    let search = springboard.searchFields.firstMatch
    let text = springboard.textFields.firstMatch
    let field = search.waitForExistence(timeout: 5) ? search : text
    XCTAssertTrue(field.waitForExistence(timeout: 15), springboard.debugDescription)
    field.tap()
    field.typeText("荷莉的手记")
    let result = springboard.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "荷莉的手记")
    ).firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 30), springboard.debugDescription)
    result.tap()

    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), springboard.debugDescription)
    let opened = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "荷莉的手记")
    ).firstMatch
    XCTAssertTrue(opened.waitForExistence(timeout: 30), app.debugDescription)
  }
}
