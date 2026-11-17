import XCTest

final class RunnerUITests: XCTestCase {
  @MainActor
  func testAccountSessionRestore() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "com.zhujinyu.wenku8flutter")
    app.launch()

    let mine = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "我的")
    ).firstMatch
    XCTAssertTrue(mine.waitForExistence(timeout: 20), app.debugDescription)
    mine.tap()

    let login = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "登录文库账号", "积分")
    ).firstMatch
    XCTAssertTrue(login.waitForExistence(timeout: 10), app.debugDescription)
    login.tap()

    let accountTitle = app.staticTexts["文库账号"].firstMatch
    XCTAssertTrue(accountTitle.waitForExistence(timeout: 15), app.debugDescription)
    let identity = app.buttons["每日签到"].firstMatch
    XCTAssertTrue(identity.waitForExistence(timeout: 30), app.debugDescription)
    XCTAssertTrue(app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "云书架")
    ).firstMatch.exists, app.debugDescription)
    print("ACCOUNT_UI_BEGIN\n\(app.debugDescription)\nACCOUNT_UI_END")
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  @MainActor
  func testReadCurrentAccountError() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "com.zhujinyu.wenku8flutter")
    app.activate()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    XCTAssertTrue(app.buttons.firstMatch.waitForExistence(timeout: 15), app.debugDescription)
    sleep(2)
    print("CURRENT_UI_BEGIN\n\(app.debugDescription)\nCURRENT_UI_END")
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  @MainActor
  func testSearchOnlineReadingAndListening() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "com.zhujinyu.wenku8flutter")
    app.launch()

    let discover = app.buttons["发现"].firstMatch
    if discover.waitForExistence(timeout: 5) { discover.tap() }
    let search = app.buttons["搜索"].firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 20), app.debugDescription)
    search.tap()
    let field = app.textFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
    field.tap()
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
    let settings = app.buttons["阅读设置"].firstMatch
    if !settings.waitForExistence(timeout: 3) { center.tap() }
    XCTAssertTrue(settings.waitForExistence(timeout: 15), app.debugDescription)
    settings.tap()
    let listen = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "听书")
    ).firstMatch
    XCTAssertTrue(listen.waitForExistence(timeout: 10), app.debugDescription)
    listen.tap()
    let play = app.buttons["开始听书"].firstMatch
    XCTAssertTrue(play.waitForExistence(timeout: 15), app.debugDescription)
    play.tap()
    XCTAssertTrue(app.buttons["暂停听书"].firstMatch.waitForExistence(timeout: 30), app.debugDescription)

    let progress = app.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH %@ AND label != %@", "当前语段 · ", "当前语段 · 准备中")
    ).firstMatch
    XCTAssertTrue(progress.waitForExistence(timeout: 45), app.debugDescription)
    print("LISTENING_UI_BEGIN\n\(app.debugDescription)\nLISTENING_UI_END")
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.buttons["停止听书"].firstMatch.tap()
  }

  @MainActor
  func testOfflineCacheReading() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "com.zhujinyu.wenku8flutter")
    app.launch()
    defer {
      app.terminate()
      app.launchArguments = []
      app.launch()
    }

    let discover = app.buttons["发现"].firstMatch
    if discover.waitForExistence(timeout: 5) { discover.tap() }
    let search = app.buttons["搜索"].firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 20), app.debugDescription)
    search.tap()
    let field = app.textFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
    if app.buttons["清空搜索"].exists { app.buttons["清空搜索"].tap() }
    field.tap()
    field.typeText("荷莉的手记\n")
    let result = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "荷莉的手记")
    ).firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 30), app.debugDescription)
    result.tap()

    let cache = app.buttons["离线缓存"].firstMatch
    XCTAssertTrue(cache.waitForExistence(timeout: 30), app.debugDescription)
    cache.tap()
    let all = app.staticTexts["缓存全部章节"].firstMatch
    XCTAssertTrue(all.waitForExistence(timeout: 10), app.debugDescription)
    all.tap()
    let completed = app.buttons.matching(
      NSPredicate(
        format: "label == %@ AND value BEGINSWITH %@ AND value ENDSWITH %@",
        "离线缓存", "缓存完成 · ", "插图 1 / 1"
      )
    ).firstMatch
    XCTAssertTrue(completed.waitForExistence(timeout: 180), app.debugDescription)
    XCTAssertFalse(app.staticTexts["插图未缓存完成"].exists, app.debugDescription)

    app.terminate()
    app.launchArguments = ["--offline-test"]
    app.launch()
    let read = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "开始阅读", "继续阅读")
    ).firstMatch
    if !read.waitForExistence(timeout: 8) {
      let offlineDiscover = app.buttons["发现"].firstMatch
      if offlineDiscover.waitForExistence(timeout: 5) { offlineDiscover.tap() }
      let offlineSearch = app.buttons["搜索"].firstMatch
      XCTAssertTrue(offlineSearch.waitForExistence(timeout: 15), app.debugDescription)
      offlineSearch.tap()
      let offlineField = app.textFields.firstMatch
      XCTAssertTrue(offlineField.waitForExistence(timeout: 10), app.debugDescription)
      if app.buttons["清空搜索"].exists { app.buttons["清空搜索"].tap() }
      offlineField.tap()
      offlineField.typeText("荷莉的手记\n")
      let cached = app.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS %@", "荷莉的手记")
      ).firstMatch
      XCTAssertTrue(cached.waitForExistence(timeout: 30), app.debugDescription)
      cached.tap()
    }
    XCTAssertTrue(read.waitForExistence(timeout: 30), app.debugDescription)
    read.tap()

    let directory = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "目录，当前第")
    ).firstMatch
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
    let chapter = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "第二章")
    ).firstMatch
    XCTAssertTrue(chapter.waitForExistence(timeout: 30), app.debugDescription)
    print("OFFLINE_UI_BEGIN\n\(app.debugDescription)\nOFFLINE_UI_END")
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

}
