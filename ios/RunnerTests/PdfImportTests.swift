import Flutter
import PDFKit
import UIKit
import XCTest
@testable import Runner

final class PdfImportTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("PdfImportTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
    try super.tearDownWithError()
  }

  func testConvertExtractsEveryPageAndWritesOfflineImages() throws {
    let source = try makePDF(pageContents: ["First page", "Second page"])
    let manifestPath = try makeConverter().convert(path: source.path, name: "示例.pdf")
    let manifestURL = URL(fileURLWithPath: manifestPath)
    let manifest = try readManifest(at: manifestURL)
    XCTAssertEqual(Set(manifest.keys), Set(["title", "pages"]))
    XCTAssertEqual(manifest["title"] as? String, "示例.pdf")
    let pages = try XCTUnwrap(manifest["pages"] as? [[String: Any]])
    XCTAssertEqual(pages.count, 2)

    for (index, page) in pages.enumerated() {
      XCTAssertEqual(Set(page.keys), Set(["title", "text", "imagePath"]))
      XCTAssertEqual(page["title"] as? String, "第 \(index + 1) 页")
      XCTAssertTrue(try XCTUnwrap(page["text"] as? String).contains(index == 0 ? "First" : "Second"))
      let imagePath = try XCTUnwrap(page["imagePath"] as? String)
      let imageURL = URL(fileURLWithPath: imagePath)
      XCTAssertTrue(imagePath.hasPrefix(manifestURL.deletingLastPathComponent().path + "/"))
      let png = try Data(contentsOf: imageURL)
      XCTAssertTrue(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
      XCTAssertNotNil(UIImage(data: png))
    }
  }

  func testPageWithoutTextLayerStillProducesReadableImage() throws {
    let source = try makePDF(pageContents: [nil])
    let manifestPath = try makeConverter().convert(path: source.path, name: "扫描书")
    let manifest = try readManifest(at: URL(fileURLWithPath: manifestPath))
    let pages = try XCTUnwrap(manifest["pages"] as? [[String: Any]])
    let page = try XCTUnwrap(pages.first)
    XCTAssertEqual(page["text"] as? String, "")
    let imagePath = try XCTUnwrap(page["imagePath"] as? String)
    let png = try Data(contentsOf: URL(fileURLWithPath: imagePath))
    XCTAssertGreaterThan(png.count, 100)
    XCTAssertNotNil(UIImage(data: png))
  }

  func testExpansionLimitRemovesPartialOutput() throws {
    let source = try makePDF(pageContents: ["Page"])
    let stagingRoot = temporaryDirectory.appendingPathComponent("Wenku8Imports", isDirectory: true)
    let converter = makeConverter(limits: PdfImportLimits(maxExpandedBytes: 1))
    XCTAssertThrowsError(try converter.convert(path: source.path, name: "超限")) { error in
      XCTAssertEqual(error as? PdfImportError, .expandedTooLarge(limit: 1))
    }
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: stagingRoot.path), [])
  }

  func testRenderSizeAndCheckedAdditionRespectLimits() throws {
    let limits = PdfImportLimits(maxImagePixels: 10_000, maxImageDimension: 100)
    let size = try PdfImportSupport.renderSize(
      for: CGRect(x: 0, y: 0, width: 1_000, height: 500), limits: limits)
    XCTAssertLessThanOrEqual(size.width, 100)
    XCTAssertLessThanOrEqual(size.height, 100)
    XCTAssertLessThanOrEqual(Int(size.width) * Int(size.height), 10_000)
    XCTAssertEqual(PdfImportSupport.checkedAdd(2, to: 8, limit: 10), 10)
    XCTAssertNil(PdfImportSupport.checkedAdd(3, to: 8, limit: 10))
  }

  func testPluginCallsBackOnMainThreadOnce() throws {
    let source = try makePDF(pageContents: ["Page"])
    let plugin = PdfImportPlugin(converter: makeConverter())
    let completed = expectation(description: "PDF 转换完成")
    completed.assertForOverFulfill = true
    var callbackCount = 0
    plugin.handle(
      FlutterMethodCall(
        methodName: "convert",
        arguments: ["path": source.path, "name": "回调测试"]
      )
    ) { value in
      XCTAssertTrue(Thread.isMainThread)
      callbackCount += 1
      let result = value as? [String: Any]
      XCTAssertNotNil(result?["manifestPath"] as? String)
      completed.fulfill()
    }
    wait(for: [completed], timeout: 10)
    XCTAssertEqual(callbackCount, 1)
  }

  private func makeConverter(limits: PdfImportLimits = .default) -> PdfImportConverter {
    PdfImportConverter(
      stagingRoot: temporaryDirectory.appendingPathComponent(
        "Wenku8Imports", isDirectory: true),
      limits: limits
    )
  }

  private func makePDF(pageContents: [String?]) throws -> URL {
    let source = temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
    let pageBounds = CGRect(x: 0, y: 0, width: 240, height: 360)
    let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
    let data = renderer.pdfData { context in
      for content in pageContents {
        context.beginPage()
        if let content {
          NSAttributedString(
            string: content,
            attributes: [.font: UIFont.systemFont(ofSize: 20)]
          ).draw(at: CGPoint(x: 24, y: 32))
        } else {
          let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 220)).image {
            imageContext in
            imageContext.cgContext.setFillColor(UIColor.systemBlue.cgColor)
            imageContext.cgContext.fill(CGRect(x: 0, y: 0, width: 160, height: 220))
            imageContext.cgContext.setFillColor(UIColor.white.cgColor)
            imageContext.cgContext.fillEllipse(in: CGRect(x: 35, y: 55, width: 90, height: 90))
          }
          image.draw(in: CGRect(x: 30, y: 50, width: 160, height: 220))
        }
      }
    }
    try data.write(to: source)
    return source
  }

  private func readManifest(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
}
