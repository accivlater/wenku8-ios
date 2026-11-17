import XCTest

@MainActor
final class DeviceCloudShelfTests: XCTestCase {
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
    let element = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label + "\n")
    ).firstMatch
    requireExists(element, 20, app)
    element.tap()
  }

  func testCloudShelfMergesIntoMainShelf() throws {
    continueAfterFailure = false
    let app = XCUIApplication(bundleIdentifier: "com.zhujinyu.wenku8flutter")
    app.launch()

    tapLabel("我的", in: app)
    let account = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "积分")
    ).firstMatch
    requireExists(account, 30, app)
    account.tap()
    requireExists(app.staticTexts["文库账号"].firstMatch, 20, app)
    tapLabel("云书架", in: app)
    requireExists(app.staticTexts["云书架"].firstMatch, 20, app)
    requireExists(
      app.staticTexts["收藏自动同步 · 联网或回到前台时自动更新"].firstMatch,
      60,
      app
    )
    XCTAssertFalse(app.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH %@", "自动同步待重试")
    ).firstMatch.exists, app.debugDescription)

    let firstCloudBook = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "移出云书架 ")
    ).firstMatch
    requireExists(firstCloudBook, 20, app)
    let bookId = firstCloudBook.label.replacingOccurrences(of: "移出云书架 ", with: "")
    XCTAssertFalse(bookId.isEmpty, app.debugDescription)
    let notMerged = app.staticTexts.matching(
      NSPredicate(format: "label ENDSWITH %@", " / CLOUD")
    ).firstMatch
    XCTAssertTrue(notMerged.waitForNonExistence(timeout: 30), app.debugDescription)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "cloud-shelf-merged"
    screenshot.lifetime = .keepAlways
    add(screenshot)

    tapLabel("返回", in: app)
    requireExists(app.staticTexts["文库账号"].firstMatch, 10, app)
    tapLabel("返回", in: app)
    tapLabel("书架", in: app)
    tapLabel("搜索书架", in: app)
    let field = app.textFields.firstMatch
    requireExists(field, 10, app)
    field.tap()
    field.typeText(bookId)
    XCTAssertFalse(app.staticTexts["没有找到相关故事"].waitForExistence(timeout: 5), app.debugDescription)
    let shelfScreenshot = XCTAttachment(screenshot: app.screenshot())
    shelfScreenshot.name = "main-shelf-cloud-book-\(bookId)"
    shelfScreenshot.lifetime = .keepAlways
    add(shelfScreenshot)
  }
}
