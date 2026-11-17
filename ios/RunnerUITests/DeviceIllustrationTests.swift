import XCTest

@MainActor
final class DeviceIllustrationTests: XCTestCase {
  private func requireExists(
    _ element: XCUIElement,
    _ timeout: TimeInterval = 20,
    _ app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertTrue(element.waitForExistence(timeout: timeout), app.debugDescription, file: file, line: line)
  }

  func testIllustrationSaveToPhotos() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "com.zhujinyu.wenku8flutter")
    app.launch()
    let discover = app.buttons["发现"].firstMatch
    if discover.waitForExistence(timeout: 5) { discover.tap() }
    app.buttons["搜索"].firstMatch.tap()
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
    let first = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "插图", "已缓存")
    ).firstMatch
    requireExists(first, 15, app)
    for _ in 0..<6 where !first.isHittable {
      app.scrollViews.firstMatch.swipeUp()
    }
    XCTAssertTrue(first.isHittable, app.debugDescription)
    first.tap()

    let image = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "章节插图，点击查看大图")
    ).firstMatch
    for _ in 0..<12 where !image.exists {
      if app.scrollViews.firstMatch.exists {
        app.scrollViews.firstMatch.swipeUp()
      } else {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.5)).tap()
      }
    }
    requireExists(image, 30, app)
    image.tap()
    let save = app.buttons["保存图片"].firstMatch
    requireExists(save, 15, app)
    save.tap()

    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    for label in ["允许添加照片", "仅本次允许", "允许", "Allow Full Access", "Allow"] {
      let button = springboard.buttons[label].firstMatch
      if button.waitForExistence(timeout: 1) {
        button.tap()
        break
      }
    }
    requireExists(save, 15, app)
    XCTAssertTrue(save.isEnabled, app.debugDescription)
    XCTAssertFalse(app.staticTexts["图片保存失败，请重试"].exists, app.debugDescription)

    let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
    photos.activate()
    let latest = photos.images.matching(
      NSPredicate(format: "label CONTAINS %@", "10月27日")
    ).firstMatch
    requireExists(latest, 20, photos)
    let screenshot = XCTAttachment(screenshot: photos.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  /// 真实在线的「插图」章节：正文里多张插图挤在同一行时，必须渲染成插图，
  /// 而不是把 `<!--image-->` 和图片地址当正文显示。
  func testIllustrationRunRendersImagesNotAddresses() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "com.zhujinyu.wenku8flutter")
    app.launch()
    let discover = app.buttons["发现"].firstMatch
    if discover.waitForExistence(timeout: 5) { discover.tap() }
    app.buttons["搜索"].firstMatch.tap()
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
    var opened = read.waitForExistence(timeout: 10)
    for attempt in 1..<4 where !opened {
      if attempt == 1 {
        result.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).tap()
      } else if attempt == 2 {
        result.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
      } else {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.17)).tap()
      }
      opened = read.waitForExistence(timeout: 10)
      if !opened { sleep(1) }
    }
    requireExists(read, opened ? 5 : 20, app)
    read.tap()

    let directory = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "目录，当前第")
    ).firstMatch
    let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    if !directory.waitForExistence(timeout: 8) { center.tap() }
    requireExists(directory, 20, app)
    directory.tap()
    let catalogue = app.staticTexts["章节目录"].firstMatch
    requireExists(catalogue, 10, app)
    catalogue.tap()

    let cachedIllustration = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "插图", "已缓存")
    ).firstMatch
    let anyIllustration = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@ AND NOT (label CONTAINS %@)", "插图", "目录")
    ).firstMatch
    let chapter = cachedIllustration.waitForExistence(timeout: 15) ? cachedIllustration : anyIllustration
    requireExists(chapter, 15, app)
    for _ in 0..<6 where !chapter.isHittable {
      app.scrollViews.firstMatch.swipeUp()
    }
    XCTAssertTrue(chapter.isHittable, app.debugDescription)
    chapter.tap()

    let image = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "章节插图，点击查看大图")
    ).firstMatch
    for _ in 0..<12 where !image.exists {
      if app.scrollViews.firstMatch.exists {
        app.scrollViews.firstMatch.swipeUp()
      } else {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.5)).tap()
      }
    }
    requireExists(image, 30, app)
    let readerShot = XCTAttachment(screenshot: app.screenshot())
    readerShot.name = "illustration-run-chapter"
    readerShot.lifetime = .keepAlways
    add(readerShot)
    XCTAssertFalse(
      app.descendants(matching: .any).matching(
        NSPredicate(
          format: "label CONTAINS %@ OR label CONTAINS %@ OR label CONTAINS %@",
          "<!--image-->", "pic.777743.xyz", "http"
        )
      ).firstMatch.exists,
      "插图章节正文里出现了 marker 或图片地址：\(app.debugDescription)"
    )
  }
}
