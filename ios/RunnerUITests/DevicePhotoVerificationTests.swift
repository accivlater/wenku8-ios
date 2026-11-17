import XCTest

@MainActor
final class DevicePhotoVerificationTests: XCTestCase {
  func testLatestSavedPhotoVisible() throws {
    let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
    photos.activate()
    let latest = photos.images.matching(
      NSPredicate(format: "label CONTAINS %@", "10月27日")
    ).firstMatch
    XCTAssertTrue(latest.waitForExistence(timeout: 20), photos.debugDescription)
    let screenshot = XCTAttachment(screenshot: photos.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }
}
