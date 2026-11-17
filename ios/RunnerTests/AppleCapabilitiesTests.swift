import CoreSpotlight
import Flutter
import XCTest
@testable import Runner

@MainActor
final class AppleCapabilitiesTests: XCTestCase {
  private let plugin = AppleCapabilitiesPlugin()

  override func setUp() {
    super.setUp()
    _ = invoke("activate")
    _ = invoke("removeAllIndexes")
    _ = invoke("deactivate")
  }

  override func tearDown() {
    _ = invoke("activate")
    _ = invoke("removeAllIndexes")
    _ = invoke("deactivate")
    super.tearDown()
  }

  func testSpotlightIndexClickAndRemovalUseRealNativeIndex() {
    let indexed = invoke("indexBooks", arguments: [
      "books": [[
        "bookId": 42,
        "title": "原生索引测试书",
        "author": "测试作者",
        "chapterTitle": "第二章",
        "position": [
          "chapter": 1,
          "chapterId": 4202,
          "paragraphIndex": 3,
          "textOffset": 17,
          "fraction": 0.5,
        ],
        "keywords": ["测试", "本地"],
      ]]
    ])
    XCTAssertNil(indexed)
    XCTAssertEqual(invoke("indexedBookIDs") as? [Int], [42])

    let activity = NSUserActivity(activityType: CSSearchableItemActionType)
    activity.userInfo = [CSSearchableItemActivityIdentifier: "book.42"]
    XCTAssertTrue(AppleCapabilitiesPlugin.handle(activity))
    let pending = invoke("activate") as? [[String: Any]]
    let action = pending?.first
    XCTAssertEqual(pending?.count, 1)
    XCTAssertEqual(action?["action"] as? String, "openBook")
    XCTAssertEqual(action?["bookId"] as? Int, 42)
    let position = action?["position"] as? [String: Any]
    XCTAssertEqual(position?["chapterId"] as? Int, 4202)
    XCTAssertEqual(position?["paragraphIndex"] as? Int, 3)
    XCTAssertEqual(position?["textOffset"] as? Int, 17)

    XCTAssertNil(invoke("removeIndexes", arguments: ["bookIds": [42]]))
    XCTAssertEqual(invoke("indexedBookIDs") as? [Int], [])
  }

  func testShortcutQuerySurvivesColdQueueAndDuplicateDelivery() {
    let activity = NSUserActivity(activityType: "org.mewx.wenku8.search-books")
    activity.userInfo = [
      "action": "searchBooks",
      "query": "荷莉的手记",
      "eventId": "duplicate-shortcut-test",
    ]
    XCTAssertTrue(AppleCapabilitiesPlugin.handle(activity))
    XCTAssertTrue(AppleCapabilitiesPlugin.handle(activity))
    let pending = invoke("activate") as? [[String: Any]]
    XCTAssertEqual(pending?.count, 1)
    XCTAssertEqual(pending?.first?["action"] as? String, "searchBooks")
    XCTAssertEqual(pending?.first?["query"] as? String, "荷莉的手记")
  }

  func testPauseShortcutOpensAppForFlutterDelivery() {
    if #available(iOS 16.0, *) {
      XCTAssertTrue(WenkuPauseListeningIntent.openAppWhenRun)
    }
  }

  func testInvalidIndexDoesNotAppearAsIndexed() {
    let response = invoke("indexBooks", arguments: [
      "books": [["bookId": 0, "title": "无效书"]]
    ])
    XCTAssertEqual((response as? FlutterError)?.code, "BAD_BOOK")
    XCTAssertEqual(invoke("indexedBookIDs") as? [Int], [])
  }

  func testReaderStatusIncludesNativeTimeAndBattery() {
    let status = ReaderStatusPlugin.currentStatus()
    print("READER_STATUS \(status)")
    let time = status["time"] as? Int ?? 0
    XCTAssertGreaterThan(time, 0)
    if let battery = status["battery"] as? Int {
      XCTAssertTrue((0...100).contains(battery))
    }
    XCTAssertNotNil(status["charging"] as? Bool)
  }

  @discardableResult
  private func invoke(_ method: String, arguments: [String: Any]? = nil) -> Any? {
    let completed = expectation(description: method)
    var response: Any?
    plugin.handle(FlutterMethodCall(methodName: method, arguments: arguments)) {
      response = $0
      completed.fulfill()
    }
    wait(for: [completed], timeout: 15)
    return response
  }
}
