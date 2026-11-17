import XCTest

@MainActor
final class DeviceReaderTests: XCTestCase {
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

  private func openSettings(_ app: XCUIApplication) {
    if app.otherElements["阅读设置"].waitForExistence(timeout: 2) { return }
    let discover = app.buttons["发现"].firstMatch
    let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    for _ in 0..<8 where !discover.exists {
      let backDetail = app.buttons["返回详情"].firstMatch
      let back = app.buttons["返回"].firstMatch
      if backDetail.exists || back.exists {
        if backDetail.isHittable { backDetail.tap() }
        else if back.isHittable { back.tap() }
        else { sleep(1) }
      } else {
        center.tap()
      }
    }
    requireExists(discover, 15, app)
    discover.tap()
    tapLabel("搜索", in: app)
    let field = app.textFields.firstMatch
    requireExists(field, 10, app)
    field.tap()
    if app.buttons["清空搜索"].exists { app.buttons["清空搜索"].tap() }
    field.typeText("荷莉的手记\n")
    let result = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "荷莉的手记")
    ).firstMatch
    requireExists(result, 30, app)
    result.tap()
    let read = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "开始阅读", "继续阅读")
    ).firstMatch
    requireExists(read, 30, app)
    read.tap()
    center.tap()
    let settings = app.buttons["阅读设置"].firstMatch
    if !settings.waitForExistence(timeout: 3) { center.tap() }
    requireExists(settings, 15, app)
    settings.tap()
    requireExists(app.otherElements["阅读设置"].firstMatch, 10, app)
  }

  private func requireSelected(_ label: String, in app: XCUIApplication) {
    let element = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@ AND selected == 1", label)
    ).firstMatch
    requireExists(element, 15, app)
  }

  func testModesAndBookmarkPersistence() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "com.zhujinyu.wenku8flutter")
    app.launch()
    openSettings(app)
    tapLabel("排版", in: app)
    tapLabel("竖排翻页", in: app)
    requireExists(app.staticTexts["文字由上往下，列由右往左；向右滑动翻到下一页。"].firstMatch, 10, app)
    tapLabel("横排翻页", in: app)
    requireExists(app.staticTexts["翻页效果"].firstMatch, 10, app)
    requireExists(app.staticTexts["翻页速度"].firstMatch, 10, app)
    tapLabel("纸页翻动", in: app)
    tapLabel("利落", in: app)
    tapLabel("上下滚动", in: app)
    XCTAssertTrue(app.staticTexts["翻页效果"].waitForNonExistence(timeout: 10), app.debugDescription)

    tapLabel("书签", in: app)
    tapLabel("添加当前位置书签", in: app)
    requireExists(app.buttons["已添加书签"].firstMatch, 15, app)
    requireExists(app.staticTexts["本书 1 个书签"].firstMatch, 10, app)

    app.terminate()
    app.launch()
    openSettings(app)
    tapLabel("书签", in: app)
    requireExists(app.staticTexts["本书 1 个书签"].firstMatch, 15, app)
    let delete = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "删除书签 ")
    ).firstMatch
    requireExists(delete, 15, app)
    delete.tap()
    requireExists(app.staticTexts["本书 0 个书签"].firstMatch, 10, app)
    requireExists(app.buttons["添加当前位置书签"].firstMatch, 10, app)
  }
}
