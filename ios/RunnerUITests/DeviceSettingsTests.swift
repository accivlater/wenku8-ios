import XCTest

@MainActor
final class DeviceSettingsTests: XCTestCase {
  private func requireExists(
    _ element: XCUIElement,
    _ timeout: TimeInterval = 20,
    _ app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertTrue(element.waitForExistence(timeout: timeout), app.debugDescription, file: file, line: line)
  }

  private func tapLabel(_ label: String, in app: XCUIApplication) {
    let button = app.buttons[label].firstMatch
    let element = button.exists
      ? button
      : app.descendants(matching: .any).matching(
          NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label + "\n")
        ).firstMatch
    requireExists(element, 20, app)
    for _ in 0..<8 where !element.isHittable {
      app.scrollViews.firstMatch.swipeUp()
    }
    XCTAssertTrue(element.isHittable, app.debugDescription)
    element.tap()
  }

  private func openSection(_ title: String, in app: XCUIApplication) {
    let discover = app.buttons["发现"].firstMatch
    let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    for _ in 0..<8 where !discover.exists {
      let backDetail = app.buttons["返回详情"].firstMatch
      let back = app.buttons["返回"].firstMatch
      if backDetail.exists || back.exists {
        if backDetail.isHittable { backDetail.tap() }
        else if back.isHittable { back.tap() }
        else { sleep(1) }
      } else if app.buttons["关闭阅读设置"].exists {
        app.buttons["关闭阅读设置"].firstMatch.tap()
      } else {
        center.tap()
      }
    }
    requireExists(discover, 15, app)
    tapLabel("我的", in: app)
    tapLabel("设置", in: app)
    tapLabel(title, in: app)
  }

  func testUsageSwitchesToggleAndRestore() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "com.zhujinyu.wenku8flutter")
    app.launch()
    openSection("使用方式", in: app)
    let switches = app.switches
    requireExists(switches.firstMatch, 15, app)
    XCTAssertEqual(switches.count, 5, app.debugDescription)
    for index in 0..<5 {
      let control = switches.element(boundBy: index)
      let original = String(describing: control.value ?? "")
      control.tap()
      sleep(1)
      XCTAssertNotEqual(original, String(describing: control.value ?? ""), app.debugDescription)
      control.tap()
      sleep(1)
      XCTAssertEqual(original, String(describing: control.value ?? ""), app.debugDescription)
    }
  }

  func testAppearanceAndKeepScreenOnPersistence() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "com.zhujinyu.wenku8flutter")
    app.launch()
    openSection("阅读与外观", in: app)
    tapLabel("外观模式", in: app)
    tapLabel("浅色", in: app)
    requireExists(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "浅色")).firstMatch, 10, app)

    let keep = app.switches.firstMatch
    requireExists(keep, 10, app)
    if String(describing: keep.value ?? "") == "0" { keep.tap() }
    XCTAssertEqual(String(describing: keep.value ?? ""), "1", app.debugDescription)

    app.terminate()
    app.launch()
    openSection("阅读与外观", in: app)
    requireExists(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "浅色")).firstMatch, 15, app)
    requireExists(keep, 10, app)
    XCTAssertEqual(String(describing: keep.value ?? ""), "1", app.debugDescription)

    keep.tap()
    XCTAssertEqual(String(describing: keep.value ?? ""), "0", app.debugDescription)
    tapLabel("外观模式", in: app)
    tapLabel("深色", in: app)
    requireExists(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "深色")).firstMatch, 10, app)
  }
}
