import XCTest

@MainActor
final class DevicePerformanceTests: XCTestCase {
  func testProfileWorkloadStaysAlive() throws {
    let app = XCUIApplication(bundleIdentifier: "com.zhujinyu.wenku8flutter")
    app.launch()
    let marker = app.descendants(matching: .any).matching(
      NSPredicate(format: "label CONTAINS %@", "星海图书馆")
    ).firstMatch
    XCTAssertTrue(marker.waitForExistence(timeout: 20), app.debugDescription)
    sleep(30)
    XCTAssertTrue(app.exists, app.debugDescription)
  }
}
