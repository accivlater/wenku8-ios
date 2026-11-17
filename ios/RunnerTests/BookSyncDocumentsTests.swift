import XCTest
@testable import Runner

final class BookSyncDocumentsTests: XCTestCase {
  private var root: URL!
  private var target: URL!
  private let sync = BookSyncDocuments()

  override func setUpWithError() throws {
    try super.setUpWithError()
    sync.disconnect()
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("BookSyncTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    target = root.appendingPathComponent("测试.wenku8sync")
    try Data().write(to: target)
  }

  override func tearDownWithError() throws {
    sync.disconnect()
    if let root { try? FileManager.default.removeItem(at: root) }
    try super.tearDownWithError()
  }

  func testWriteConflictAndRecoveryPreserveBothVersions() throws {
    try sync.select(target, created: true)
    XCTAssertEqual(sync.info()?["created"] as? Bool, true)
    let initial = try sync.read()
    let before = try XCTUnwrap(initial["path"] as? String)
    let next = try XCTUnwrap(initial["outputPath"] as? String)
    try Data("第一版".utf8).write(to: URL(fileURLWithPath: next))
    try sync.write(arguments: ["path": next, "expectedPath": before])
    XCTAssertEqual(try Data(contentsOf: target), Data("第一版".utf8))
    XCTAssertEqual(sync.info()?["created"] as? Bool, false)

    let second = try sync.read()
    let secondBefore = try XCTUnwrap(second["path"] as? String)
    let secondNext = try XCTUnwrap(second["outputPath"] as? String)
    try Data("第二版".utf8).write(to: URL(fileURLWithPath: secondNext))
    try Data("外部修改".utf8).write(to: target)
    XCTAssertThrowsError(
      try sync.write(arguments: ["path": secondNext, "expectedPath": secondBefore])
    ) { error in
      XCTAssertTrue(error.localizedDescription.contains("发生变化"))
    }
    XCTAssertEqual(try Data(contentsOf: target), Data("外部修改".utf8))

    let recoveryNext = try XCTUnwrap(sync.recover(which: "next"))
    let recoveryBefore = try XCTUnwrap(sync.recover(which: "before"))
    XCTAssertEqual(
      try String(data: Data(contentsOf: URL(fileURLWithPath: recoveryNext)), encoding: .utf8),
      "第一版"
    )
    XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: recoveryBefore)).count, 0)
    sync.disconnect()
    XCTAssertNil(sync.info())
  }

  func testNewConnectionCanWriteAnEmptyCloudFile() throws {
    try sync.select(target, created: true)
    let initial = try sync.read()
    let before = try XCTUnwrap(initial["path"] as? String)
    let next = try XCTUnwrap(initial["outputPath"] as? String)
    XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: before)).count, 0)
    try Data("有效同步".utf8).write(to: URL(fileURLWithPath: next))
    try sync.write(arguments: ["path": next, "expectedPath": before])
    XCTAssertEqual(try Data(contentsOf: target), Data("有效同步".utf8))
  }
}
