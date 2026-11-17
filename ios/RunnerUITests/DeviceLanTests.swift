import XCTest

@MainActor
final class DeviceLanTests: XCTestCase {
  func testLanPermissionDiscoveryAndDisable() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "com.zhujinyu.wenku8flutter")
    app.launch()
    let mine = app.buttons["我的"].firstMatch
    XCTAssertTrue(mine.waitForExistence(timeout: 20), app.debugDescription)
    mine.tap()
    app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "设置")).firstMatch.tap()
    let lan = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH %@", "局域网续读")
    ).firstMatch
    XCTAssertTrue(lan.waitForExistence(timeout: 15), app.debugDescription)
    lan.tap()

    let toggle = app.switches.firstMatch
    XCTAssertTrue(toggle.waitForExistence(timeout: 15), app.debugDescription)
    if String(describing: toggle.value ?? "") == "0" { toggle.swipeRight() }
    sleep(5)
    app.scrollViews.firstMatch.swipeUp()
    XCTAssertEqual(String(describing: toggle.value ?? ""), "1", app.debugDescription)
    let refresh = app.buttons["重新发现"].firstMatch
    XCTAssertTrue(refresh.waitForExistence(timeout: 15), app.debugDescription)
    refresh.tap()
    let nearby = app.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH %@", "还没有发现新设备")
    ).firstMatch
    XCTAssertTrue(nearby.waitForExistence(timeout: 20), app.debugDescription)
    XCTAssertFalse(app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "本地网络权限")
    ).firstMatch.exists, app.debugDescription)
    toggle.swipeLeft()
    XCTAssertEqual(String(describing: toggle.value ?? ""), "0", app.debugDescription)
  }
}
