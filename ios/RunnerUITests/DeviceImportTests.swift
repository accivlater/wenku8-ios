import XCTest

@MainActor
final class DeviceImportTests: XCTestCase {
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

  private func openLocal(_ app: XCUIApplication) {
    let local = app.buttons["本地"].firstMatch
    requireExists(local, 20, app)
    local.tap()
    requireExists(app.buttons["导入书籍"].firstMatch, 15, app)
  }

  private func importBook(
    _ app: XCUIApplication,
    fileName: String,
    title: String,
    body: String
  ) {
    openLocal(app)
    app.buttons["导入书籍"].firstMatch.tap()
    let choices = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", "导入书籍")
    )
    requireExists(choices.firstMatch, 10, app)
    choices.element(boundBy: choices.count - 1).tap()

    let browse = app.buttons["浏览"].firstMatch
    requireExists(browse, 15, app)
    browse.tap()
    let folder = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH %@", "轻小说文库")
    ).firstMatch
    if !folder.waitForExistence(timeout: 2) {
      let myPhone = app.descendants(matching: .any).matching(
        NSPredicate(format: "label BEGINSWITH %@", "我的iPhone")
      ).firstMatch
      requireExists(myPhone, 10, app)
      myPhone.tap()
      requireExists(folder, 10, app)
    }
    if folder.elementType == .cell { folder.tap() }

    let pickerSearch = app.searchFields.firstMatch
    requireExists(pickerSearch, 10, app)
    pickerSearch.tap()
    pickerSearch.typeText(fileName)
    let parts = fileName.split(separator: ".")
    let baseName = parts.first.map(String.init) ?? fileName
    let suffix = parts.last.map(String.init) ?? fileName
    let file = app.cells.matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND (identifier CONTAINS %@ OR label CONTAINS %@)",
        baseName, suffix, suffix
      )
    ).firstMatch
    requireExists(file, 20, app)
    file.tap()
    let open = app.buttons["打开"].firstMatch
    requireExists(open, 10, app)
    open.tap()

    let book = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH %@", title)
    ).firstMatch
    requireExists(book, 60, app)
    book.tap()
    let read = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "开始阅读", "继续阅读")
    ).firstMatch
    requireExists(read, 30, app)
    read.tap()
    let content = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", body)
    ).firstMatch
    requireExists(content, 30, app)

    app.terminate()
    app.launch()
    openLocal(app)
    let restored = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH %@", title)
    ).firstMatch
    requireExists(restored, 20, app)
    restored.tap()
    requireExists(read, 30, app)
    read.tap()
    requireExists(content, 30, app)
  }

  func testTxtImportReadAndReopen() throws {
    continueAfterFailure = false
    let app = launchApp()
    importBook(
      app,
      fileName: "ios-sample.txt",
      title: "ios-sample",
      body: "这是用于验证 iOS 本地导入的第一段正文"
    )
  }

  func testEpubImportReadAndReopen() throws {
    continueAfterFailure = false
    let app = launchApp()
    importBook(
      app,
      fileName: "ios-sample.epub",
      title: "iOS EPUB 验证书",
      body: "这段 EPUB 正文用于验证 iOS 的目录、排版与离线阅读"
    )
  }

  func testAzw3ImportReadAndReopen() throws {
    continueAfterFailure = false
    let app = launchApp()
    importBook(
      app,
      fileName: "kf8-multi.azw3",
      title: "MOBI 中文书名",
      body: "图前中文"
    )
  }

  func testDocImportReadAndReopen() throws {
    continueAfterFailure = false
    let app = launchApp()
    importBook(
      app,
      fileName: "word-0table.doc",
      title: "word-0table",
      body: "图前中文"
    )
  }

  func testHtmlImportReadAndReopen() throws {
    continueAfterFailure = false
    let app = launchApp()
    importBook(
      app,
      fileName: "word-cp1252.html",
      title: "Word CP1252 sample",
      body: "café"
    )
  }

  func testMobiImportReadAndReopen() throws {
    continueAfterFailure = false
    let app = launchApp()
    importBook(app, fileName: "Kindle.mobi", title: "MOBI 格式一甲", body: "图前中文")
  }

  func testAzwImportReadAndReopen() throws {
    continueAfterFailure = false
    let app = launchApp()
    importBook(app, fileName: "Kindle.azw", title: "MOBI 格式二乙", body: "图前中文")
  }

  func testPrcImportReadAndReopen() throws {
    continueAfterFailure = false
    let app = launchApp()
    importBook(app, fileName: "Kindle.prc", title: "MOBI 格式三丙", body: "图前中文")
  }

  func testFb2ImportReadAndReopen() throws {
    continueAfterFailure = false
    let app = launchApp()
    importBook(app, fileName: "中文小说.fb2", title: "中文小说", body: "FB2 真机正文")
  }

  func testMarkdownImportReadAndReopen() throws {
    continueAfterFailure = false
    let app = launchApp()
    importBook(app, fileName: "笔记.md", title: "笔记", body: "Markdown 真机正文")
  }

  func testRtfImportReadAndReopen() throws {
    continueAfterFailure = false
    let app = launchApp()
    importBook(app, fileName: "真机.rtf", title: "真机", body: "RTF device body")
  }

  func testDocxImportReadAndReopen() throws {
    continueAfterFailure = false
    let app = launchApp()
    importBook(app, fileName: "DOCX文档.docx", title: "DOCX文档", body: "DOCX 真机正文")
  }

  func testPdfImportReadAndReopen() throws {
    continueAfterFailure = false
    let app = launchApp()
    importBook(app, fileName: "PDF文档.pdf", title: "PDF文档", body: "PDF device body")
  }
}
