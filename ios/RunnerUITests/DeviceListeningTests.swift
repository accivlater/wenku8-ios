import XCTest

@MainActor
final class DeviceListeningTests: XCTestCase {
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

  private func openListening(_ app: XCUIApplication) {
    let discover = app.buttons["发现"].firstMatch
    let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    for _ in 0..<8 where !discover.exists {
      let backDetail = app.buttons["返回详情"].firstMatch
      let back = app.buttons["返回"].firstMatch
      if backDetail.exists || back.exists {
        if backDetail.isHittable {
          backDetail.tap()
        } else if back.isHittable {
          back.tap()
        } else {
          sleep(1)
        }
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
    let directory = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "目录，当前第")
    ).firstMatch
    requireExists(directory, 30, app)
    directory.tap()
    let catalogue = app.staticTexts["章节目录"].firstMatch
    requireExists(catalogue, 10, app)
    catalogue.tap()
    let second = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "第二章")
    ).firstMatch
    requireExists(second, 15, app)
    second.tap()
    center.tap()
    let settings = app.buttons["阅读设置"].firstMatch
    if !settings.waitForExistence(timeout: 3) { center.tap() }
    requireExists(settings, 15, app)
    settings.tap()
    tapLabel("听书", in: app)
    requireExists(app.buttons["开始听书"].firstMatch, 15, app)
  }

  func testAppleSpeechBackgroundPauseResumeAndStop() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "com.zhujinyu.wenku8flutter")
    app.launch()
    openListening(app)

    tapLabel("选择系统朗读引擎", in: app)
    let engine = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "Apple")
    ).firstMatch
    requireExists(engine, 20, app)
    engine.tap()
    let source = app.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH %@", "当前音源 · 系统引擎")
    ).firstMatch
    requireExists(source, 15, app)

    for _ in 0..<6 { app.scrollViews.firstMatch.swipeDown() }
    tapLabel("开始听书", in: app)
    let pause = app.buttons["暂停听书"].firstMatch
    requireExists(pause, 30, app)
    let progress = app.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH %@ AND label != %@", "当前语段 · ", "当前语段 · 准备中")
    ).firstMatch
    requireExists(progress, 45, app)
    let before = progress.label

    XCUIDevice.shared.press(.home)
    sleep(6)
    app.activate()
    requireExists(pause, 15, app)
    requireExists(progress, 15, app)
    XCTAssertNotEqual(before, progress.label, app.debugDescription)

    pause.tap()
    requireExists(app.buttons["开始听书"].firstMatch, 15, app)
    tapLabel("开始听书", in: app)
    requireExists(pause, 20, app)
    app.buttons["停止听书"].firstMatch.tap()
    requireExists(app.buttons["开始听书"].firstMatch, 15, app)
    tapLabel("自然在线", in: app)
    requireExists(app.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH %@", "当前音源 · 自然在线")
    ).firstMatch, 15, app)
  }
}
