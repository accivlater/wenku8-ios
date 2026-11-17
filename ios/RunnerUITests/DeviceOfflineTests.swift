import XCTest

@MainActor
final class DeviceOfflineTests: XCTestCase {
  func testAirplaneModeCachedChapterAndRecovery() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "com.zhujinyu.wenku8flutter")
    app.launch()
    let discover = app.buttons["发现"].firstMatch
    XCTAssertTrue(discover.waitForExistence(timeout: 20), app.debugDescription)
    discover.tap()
    app.buttons["搜索"].firstMatch.tap()
    let field = app.textFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
    field.tap()
    if app.buttons["清空搜索"].exists { app.buttons["清空搜索"].tap() }
    field.typeText("荷莉的手记\n")
    let result = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "荷莉的手记")
    ).firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 30), app.debugDescription)
    result.tap()
    let read = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "开始阅读", "继续阅读")
    ).firstMatch
    XCTAssertTrue(read.waitForExistence(timeout: 30), app.debugDescription)
    read.tap()
    let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    center.tap()
    let directory = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "目录，当前第")
    ).firstMatch
    if !directory.waitForExistence(timeout: 3) { center.tap() }
    XCTAssertTrue(directory.waitForExistence(timeout: 30), app.debugDescription)
    directory.tap()
    let catalogue = app.staticTexts["章节目录"].firstMatch
    XCTAssertTrue(catalogue.waitForExistence(timeout: 10), app.debugDescription)
    catalogue.tap()
    let second = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "第二章")
    ).firstMatch
    XCTAssertTrue(second.waitForExistence(timeout: 15), app.debugDescription)
    second.tap()

    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    settings.activate()
    let airplane = settings.switches.element(boundBy: 1)
    XCTAssertTrue(airplane.waitForExistence(timeout: 15), settings.debugDescription)
    if String(describing: airplane.value ?? "") == "0" { airplane.tap() }
    XCTAssertEqual(String(describing: airplane.value ?? ""), "1", settings.debugDescription)
    defer {
      settings.activate()
      if String(describing: airplane.value ?? "") == "1" { airplane.tap() }
      app.activate()
    }

    app.activate()
    let next = app.buttons["下一章"].firstMatch
    XCTAssertTrue(next.waitForExistence(timeout: 15), app.debugDescription)
    next.tap()
    let third = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "第三章")
    ).firstMatch
    XCTAssertTrue(third.waitForExistence(timeout: 30), app.debugDescription)

    settings.activate()
    airplane.tap()
    XCTAssertEqual(String(describing: airplane.value ?? ""), "0", settings.debugDescription)
    app.activate()
    XCTAssertTrue(third.waitForExistence(timeout: 15), app.debugDescription)
  }

  func testDisableAirplaneMode() throws {
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    settings.activate()
    let airplane = settings.switches.element(boundBy: 1)
    XCTAssertTrue(airplane.waitForExistence(timeout: 15), settings.debugDescription)
    if String(describing: airplane.value ?? "") == "1" { airplane.tap() }
    XCTAssertEqual(String(describing: airplane.value ?? ""), "0", settings.debugDescription)
  }
}
