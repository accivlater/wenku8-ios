import XCTest

@MainActor
final class DeviceShortcutTests: XCTestCase {
  func testDiscoverAppShortcutActions() throws {
    continueAfterFailure = false
    let bundle = "com.zhujinyu.wenku8flutter"
    let app = XCUIApplication(bundleIdentifier: bundle)
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), app.debugDescription)
    sleep(2)

    let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
    shortcuts.launch()
    let newShortcut = shortcuts.buttons["新建快捷指令"].firstMatch
    if newShortcut.waitForExistence(timeout: 3) {
      newShortcut.tap()
    } else {
      shortcuts.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.925)).tap()
    }
    let field = shortcuts.searchFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 15), shortcuts.debugDescription)
    field.tap()
    field.typeText("轻小说文库")
    let result = shortcuts.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "轻小说文库")
    ).firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 20), shortcuts.debugDescription)
    result.tap()
    sleep(2)
    print("SHORTCUT_ACTIONS_BEGIN\n\(shortcuts.debugDescription)\nSHORTCUT_ACTIONS_END")
    let screenshot = XCTAttachment(screenshot: shortcuts.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
    for title in ["继续阅读", "搜索书籍", "开始听书", "暂停听书"] {
      let action = shortcuts.descendants(matching: .any).matching(
        NSPredicate(format: "label == %@", title)
      ).firstMatch
      XCTAssertTrue(action.waitForExistence(timeout: 10), "缺少动作 \(title)\n\(shortcuts.debugDescription)")
    }
  }

  func testContinueReadingShortcutOpensReader() throws {
    continueAfterFailure = false
    let bundle = "com.zhujinyu.wenku8flutter"
    let app = XCUIApplication(bundleIdentifier: bundle)
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), app.debugDescription)
    sleep(2)

    let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
    shortcuts.launch()
    let newShortcut = shortcuts.buttons["新建快捷指令"].firstMatch
    if newShortcut.waitForExistence(timeout: 3) {
      newShortcut.tap()
    } else {
      shortcuts.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.925)).tap()
    }
    let field = shortcuts.searchFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 15), shortcuts.debugDescription)
    field.tap()
    field.typeText("轻小说文库")
    let result = shortcuts.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "轻小说文库")
    ).firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 20), shortcuts.debugDescription)
    result.tap()
    let action = shortcuts.cells["继续阅读"].firstMatch
    XCTAssertTrue(action.waitForExistence(timeout: 15), shortcuts.debugDescription)
    action.tap()
    sleep(2)
    print("SHORTCUT_EDITOR_BEGIN\n\(shortcuts.debugDescription)\nSHORTCUT_EDITOR_END")
    let run = shortcuts.buttons["播放"].firstMatch
    XCTAssertTrue(run.waitForExistence(timeout: 15), shortcuts.debugDescription)
    run.tap()

    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), shortcuts.debugDescription)
    let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    center.tap()
    let readerSettings = app.buttons["阅读设置"].firstMatch
    if !readerSettings.waitForExistence(timeout: 3) { center.tap() }
    XCTAssertTrue(readerSettings.waitForExistence(timeout: 15), app.debugDescription)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  private func addAndRun(_ title: String, query: String? = nil) {
    let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
    shortcuts.launch()
    let dismissMissing = shortcuts.buttons["好"].firstMatch
    if dismissMissing.waitForExistence(timeout: 1) { dismissMissing.tap() }
    let newShortcut = shortcuts.buttons["新建快捷指令"].firstMatch
    if newShortcut.waitForExistence(timeout: 3) {
      newShortcut.tap()
    } else {
      shortcuts.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.925)).tap()
    }
    let field = shortcuts.searchFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 15), shortcuts.debugDescription)
    field.tap()
    field.typeText("轻小说文库")
    let result = shortcuts.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "轻小说文库")
    ).firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 20), shortcuts.debugDescription)
    result.tap()
    let action = shortcuts.cells[title].firstMatch
    XCTAssertTrue(action.waitForExistence(timeout: 15), shortcuts.debugDescription)
    action.tap()
    if let query {
      let input = shortcuts.textFields.firstMatch
      XCTAssertTrue(input.waitForExistence(timeout: 10), shortcuts.debugDescription)
      input.tap()
      input.typeText(query)
      let done = shortcuts.keyboards.buttons["完成"].firstMatch
      let englishDone = shortcuts.keyboards.buttons["Done"].firstMatch
      let returnKey = shortcuts.keyboards.buttons["return"].firstMatch
      if done.exists {
        done.tap()
      } else if englishDone.exists {
        englishDone.tap()
      } else if returnKey.exists {
        returnKey.tap()
      } else {
        shortcuts.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.2)).tap()
      }
    }
    let run = shortcuts.buttons["播放"].firstMatch
    XCTAssertTrue(run.waitForExistence(timeout: 15), shortcuts.debugDescription)
    run.tap()
  }

  func testSearchBooksShortcutPassesQuery() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "com.zhujinyu.wenku8flutter")
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), app.debugDescription)
    sleep(2)
    addAndRun("搜索书籍", query: "荷莉的手记")
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), app.debugDescription)
    print("SEARCH_ACTION_APP_BEGIN\n\(app.debugDescription)\nSEARCH_ACTION_APP_END")
    let result = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "荷莉的手记")
    ).firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 30), app.debugDescription)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  private func runDirect(_ title: String) {
    let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
    shortcuts.launch()
    let name = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
    XCUIDevice.shared.system.open(URL(string: "shortcuts://run-shortcut?name=\(name)")!)
  }

  func testListeningShortcutsStartAndPause() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "com.zhujinyu.wenku8flutter")
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), app.debugDescription)
    sleep(2)
    runDirect("开始听书")
    let activeSession = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "正在听书 · ")
    ).firstMatch
    XCTAssertTrue(activeSession.waitForExistence(timeout: 45), app.debugDescription)
    activeSession.tap()
    XCTAssertTrue(app.buttons["暂停听书"].firstMatch.waitForExistence(timeout: 15), app.debugDescription)
    runDirect("暂停听书")
    XCTAssertTrue(app.buttons["开始听书"].firstMatch.waitForExistence(timeout: 20), app.debugDescription)
    XCTAssertFalse(app.buttons["暂停听书"].exists, app.debugDescription)
  }
}
