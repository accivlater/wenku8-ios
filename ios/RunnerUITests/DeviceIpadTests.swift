import XCTest

@MainActor
final class DeviceIpadTests: XCTestCase {
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

  private func attach(_ name: String) {
    let screenshot = XCTAttachment(screenshot: XCUIApplication(bundleIdentifier: "com.zhujinyu.wenku8flutter").screenshot())
    screenshot.name = name
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  func testNativeRotationCatalogueModesListeningAndBackState() throws {
    continueAfterFailure = false
    guard UIDevice.current.userInterfaceIdiom == .pad else {
      throw XCTSkip("iPad only")
    }
    let app = XCUIApplication(bundleIdentifier: "com.zhujinyu.wenku8flutter")
    app.activate()
    XCUIDevice.shared.orientation = .portrait
    let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    let read = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "开始阅读", "继续阅读")
    ).firstMatch
    requireExists(read, 20, app)
    attach("ipad-portrait-detail")
    XCUIDevice.shared.orientation = .landscapeLeft
    sleep(2)
    requireExists(read, 15, app)
    attach("ipad-landscape-detail")
    read.tap()

    let directory = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "目录，当前第")
    ).firstMatch
    center.tap()
    if !directory.waitForExistence(timeout: 3) { center.tap() }
    requireExists(directory, 20, app)
    attach("ipad-landscape-reader")
    XCUIDevice.shared.orientation = .portrait
    sleep(2)
    requireExists(directory, 15, app)
    attach("ipad-portrait-reader")
    directory.tap()
    let catalogue = app.staticTexts["章节目录"].firstMatch
    requireExists(catalogue, 10, app)
    catalogue.tap()
    let second = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "第二章")
    ).firstMatch
    requireExists(second, 15, app)
    second.tap()
    let chapter = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "第二章")
    ).firstMatch
    requireExists(chapter, 30, app)
    XCUIDevice.shared.orientation = .landscapeLeft
    sleep(2)
    requireExists(chapter, 15, app)
    attach("ipad-landscape-second-chapter")

    center.tap()
    let settings = app.buttons["阅读设置"].firstMatch
    if !settings.waitForExistence(timeout: 3) { center.tap() }
    requireExists(settings, 15, app)
    settings.tap()
    tapLabel("排版", in: app)
    tapLabel("竖排翻页", in: app)
    requireExists(app.staticTexts["文字由上往下，列由右往左；向右滑动翻到下一页。"].firstMatch, 10, app)
    tapLabel("横排翻页", in: app)
    requireExists(app.staticTexts["翻页效果"].firstMatch, 10, app)
    tapLabel("上下滚动", in: app)
    XCTAssertTrue(app.staticTexts["翻页效果"].waitForNonExistence(timeout: 10), app.debugDescription)

    tapLabel("听书", in: app)
    let play = app.buttons["开始听书"].firstMatch
    requireExists(play, 15, app)
    play.tap()
    let pause = app.buttons["暂停听书"].firstMatch
    requireExists(pause, 30, app)
    let progress = app.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH %@ AND label != %@", "当前语段 · ", "当前语段 · 准备中")
    ).firstMatch
    requireExists(progress, 45, app)
    attach("ipad-listening-started")
    pause.tap()
    requireExists(app.buttons["开始听书"].firstMatch, 15, app)
    attach("ipad-listening-paused")
    app.buttons["停止听书"].firstMatch.tap()

    tapLabel("关闭阅读设置", in: app)
    center.tap()
    let backDetail = app.buttons["返回详情"].firstMatch
    requireExists(backDetail, 15, app)
    backDetail.tap()
    requireExists(read, 20, app)
    attach("ipad-detail-after-reader")
  }
}
