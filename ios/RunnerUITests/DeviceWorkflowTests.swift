import XCTest

@MainActor
final class DeviceWorkflowTests: XCTestCase {
  private func launchApp() -> XCUIApplication {
    let app = XCUIApplication(bundleIdentifier: "com.zhujinyu.wenku8flutter")
    app.launch()
    return app
  }

  private func requireExists(
    _ element: XCUIElement,
    _ timeout: TimeInterval = 20,
    _ app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertTrue(element.waitForExistence(timeout: timeout), app.debugDescription, file: file, line: line)
  }

  private func tapLabel(_ label: String, in app: XCUIApplication, timeout: TimeInterval = 20) {
    let button = app.buttons[label].firstMatch
    let element: XCUIElement
    if button.waitForExistence(timeout: 2) {
      element = button
    } else {
      element = app.descendants(matching: .any).matching(
        NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label + "\n")
      ).firstMatch
    }
    requireExists(element, timeout, app)
    for _ in 0..<6 where !element.isHittable {
      app.scrollViews.firstMatch.swipeUp()
    }
    XCTAssertTrue(element.isHittable, app.debugDescription)
    element.tap()
  }

  private func openDetail(_ app: XCUIApplication) {
    let discover = app.buttons["发现"].firstMatch
    if discover.waitForExistence(timeout: 5) { discover.tap() }
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
    requireExists(app.staticTexts["图书详情"].firstMatch, 30, app)
  }

  private func openBackup(_ app: XCUIApplication) {
    tapLabel("我的", in: app)
    tapLabel("设置", in: app)
    tapLabel("数据与存储", in: app)
    tapLabel("备份与恢复", in: app)
    requireExists(app.staticTexts["带走你的阅读记录"].firstMatch, 15, app)
  }

  private func cancelSystemPanel(_ app: XCUIApplication) {
    let labels = ["取消", "关闭", "Cancel", "Close"]
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    for target in [app, springboard] {
      for label in labels {
        let element = target.descendants(matching: .any).matching(
          NSPredicate(format: "label == %@", label)
        ).firstMatch
        guard element.waitForExistence(timeout: 2) else { continue }
        element.tap()
        if element.waitForNonExistence(timeout: 2) { return }
        let frame = element.frame
        let screen = target.frame
        target.coordinate(withNormalizedOffset: CGVector(
          dx: (frame.midX - screen.minX) / screen.width,
          dy: (frame.midY - screen.minY) / screen.height
        )).tap()
        if element.waitForNonExistence(timeout: 5) { return }
        XCTFail(app.debugDescription)
        return
      }
    }
    XCTFail(app.debugDescription)
  }

  func testDetailSystemShareCancel() throws {
    continueAfterFailure = false
    let app = launchApp()
    openDetail(app)
    tapLabel("分享", in: app)
    let shareEvidence = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "拷贝", "Copy")
    ).firstMatch
    requireExists(shareEvidence, 20, app)
    let dismiss = app.otherElements["PopoverDismissRegion"].firstMatch
    requireExists(dismiss, 5, app)
    dismiss.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
    XCTAssertTrue(shareEvidence.waitForNonExistence(timeout: 10), app.debugDescription)
    requireExists(app.staticTexts["图书详情"].firstMatch, 10, app)
  }

  func testBackupClipboardPreviewAndCancel() throws {
    continueAfterFailure = false
    let app = launchApp()
    openBackup(app)
    tapLabel("复制备份文本", in: app)
    tapLabel("从剪贴板读取备份", in: app)
    requireExists(app.staticTexts["恢复预览"].firstMatch, 15, app)
    requireExists(app.buttons["确认合并恢复"].firstMatch, 5, app)
    tapLabel("取消恢复", in: app)
    XCTAssertFalse(app.staticTexts["恢复预览"].exists, app.debugDescription)
    requireExists(app.staticTexts["带走你的阅读记录"].firstMatch, 5, app)
  }

  func testBackupFilesExportAndImportCancel() throws {
    continueAfterFailure = false
    let app = launchApp()
    openBackup(app)

    func dismissPicker() {
      let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
      let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
      start.press(forDuration: 0.15, thenDragTo: end)
      let title = app.staticTexts["带走你的阅读记录"].firstMatch
      requireExists(title, 10, app)
      XCTAssertTrue(title.isHittable, app.debugDescription)
      XCTAssertFalse(app.otherElements["Cancel"].exists, app.debugDescription)
    }

    tapLabel("导出备份文件", in: app)
    requireExists(app.buttons["保存"].firstMatch, 20, app)
    dismissPicker()
    XCTAssertTrue(app.buttons["导出备份文件"].firstMatch.isEnabled, app.debugDescription)

    tapLabel("选择备份文件", in: app)
    requireExists(app.otherElements["Cancel"].firstMatch, 20, app)
    dismissPicker()
    XCTAssertTrue(app.buttons["选择备份文件"].firstMatch.isEnabled, app.debugDescription)

    tapLabel("导出备份文件", in: app)
    requireExists(app.buttons["保存"].firstMatch, 20, app)
    dismissPicker()
    XCTAssertTrue(app.buttons["导出备份文件"].firstMatch.isEnabled, app.debugDescription)
  }

  func testShortSearchEndsWithoutFooterFlicker() throws {
    continueAfterFailure = false
    let app = launchApp()
    let discover = app.buttons["发现"].firstMatch
    if discover.waitForExistence(timeout: 5) { discover.tap() }
    tapLabel("搜索", in: app)
    let field = app.textFields.firstMatch
    requireExists(field, 10, app)
    field.tap()
    if app.buttons["清空搜索"].exists { app.buttons["清空搜索"].tap() }
    field.typeText("魔法禁书\n")
    let result = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "魔法禁书目录")
    ).firstMatch
    requireExists(result, 30, app)
    let end = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "已经到底了")
    ).firstMatch
    for _ in 0..<12 where !end.exists {
      app.scrollViews.firstMatch.swipeUp()
      sleep(1)
    }
    requireExists(end, 45, app)
    XCTAssertFalse(app.buttons["加载更多"].exists, app.debugDescription)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  func testAboutShowsProductDescription() throws {
    continueAfterFailure = false
    let app = launchApp()
    tapLabel("我的", in: app)
    tapLabel("关于", in: app)
    let description = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "一款用于发现、收藏和阅读轻小说的阅读器")
    ).firstMatch
    requireExists(description, 15, app)
    requireExists(app.staticTexts["关于轻小说文库"].firstMatch, 10, app)
    let licenses = app.buttons["开源许可与字体授权"].firstMatch
    for _ in 0..<8 where !licenses.exists {
      app.scrollViews.firstMatch.swipeUp()
    }
    requireExists(licenses, 10, app)
    for forbidden in ["MewX", "1131397088", "本版更新", "项目介绍与下载"] {
      XCTAssertFalse(app.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS %@", forbidden)
      ).firstMatch.exists, "关于页仍包含原内容：\(forbidden)\n\(app.debugDescription)")
    }
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }
}
