import Flutter
import PDFKit
import UIKit

struct PdfImportLimits {
  let maxSourceBytes: Int
  let maxPages: Int
  let maxExpandedBytes: Int
  let maxImagePixels: Int
  let maxImageDimension: Int
  let maxImageBytes: Int
  let maxOutputBytes: Int

  init(
    maxSourceBytes: Int = 512 * 1024 * 1024,
    maxPages: Int = 1_000,
    maxExpandedBytes: Int = 2 * 1024 * 1024 * 1024,
    maxImagePixels: Int = 24_000_000,
    maxImageDimension: Int = 8_192,
    maxImageBytes: Int = 24 * 1024 * 1024,
    maxOutputBytes: Int = 512 * 1024 * 1024
  ) {
    self.maxSourceBytes = maxSourceBytes
    self.maxPages = maxPages
    self.maxExpandedBytes = maxExpandedBytes
    self.maxImagePixels = maxImagePixels
    self.maxImageDimension = maxImageDimension
    self.maxImageBytes = maxImageBytes
    self.maxOutputBytes = maxOutputBytes
  }

  static let `default` = PdfImportLimits()
}

enum PdfImportError: LocalizedError, Equatable {
  case badRequest
  case unreadable
  case encrypted
  case sourceTooLarge(limit: Int)
  case emptyDocument
  case tooManyPages(limit: Int)
  case invalidPage(index: Int)
  case expandedTooLarge(limit: Int)
  case imageTooLarge(index: Int, limit: Int)
  case outputTooLarge(limit: Int)
  case renderFailed(index: Int)
  case writeFailed
  case conversionFailed

  var code: String {
    switch self {
    case .badRequest: return "BAD_REQUEST"
    case .unreadable: return "PDF_UNREADABLE"
    case .encrypted: return "ENCRYPTED_PDF"
    case .sourceTooLarge: return "SOURCE_TOO_LARGE"
    case .emptyDocument: return "EMPTY_PDF"
    case .tooManyPages: return "TOO_MANY_PAGES"
    case .invalidPage: return "INVALID_PAGE"
    case .expandedTooLarge: return "EXPANDED_TOO_LARGE"
    case .imageTooLarge: return "IMAGE_TOO_LARGE"
    case .outputTooLarge: return "OUTPUT_TOO_LARGE"
    case .renderFailed: return "RENDER_FAILED"
    case .writeFailed: return "WRITE_FAILED"
    case .conversionFailed: return "CONVERT_FAILED"
    }
  }

  var message: String {
    switch self {
    case .badRequest:
      return "PDF 转换参数不完整，请重新选择文件"
    case .unreadable:
      return "无法读取 PDF，请确认文件存在且可访问"
    case .encrypted:
      return "不支持加密、受密码保护或禁止内容提取的 PDF，请选择未加密文件"
    case .sourceTooLarge(let limit):
      return "PDF 文件超过 \(PdfImportSupport.byteCountDescription(limit)) 大小限制"
    case .emptyDocument:
      return "PDF 没有可转换的页面"
    case .tooManyPages(let limit):
      return "PDF 页数超过限制，最多支持 \(limit) 页"
    case .invalidPage(let index):
      return "PDF 第 \(index + 1) 页尺寸无效，无法转换"
    case .expandedTooLarge(let limit):
      return "PDF 页面展开后超过 \(PdfImportSupport.byteCountDescription(limit)) 总量限制，请拆分或压缩原文件"
    case .imageTooLarge(let index, let limit):
      return "PDF 第 \(index + 1) 页图片超过单张 \(PdfImportSupport.byteCountDescription(limit)) 限制"
    case .outputTooLarge(let limit):
      return "PDF 转换结果超过 \(PdfImportSupport.byteCountDescription(limit)) 输出限制"
    case .renderFailed(let index):
      return "PDF 第 \(index + 1) 页渲染失败"
    case .writeFailed:
      return "无法保存 PDF 转换结果，请检查可用存储空间后重试"
    case .conversionFailed:
      return "PDF 转换失败，请确认文件完整后重试"
    }
  }

  var errorDescription: String? { message }
}

enum PdfImportSupport {
  static func title(name: String, source: URL) -> String {
    let requested = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !requested.isEmpty { return requested }
    let derived = source.deletingPathExtension().lastPathComponent
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return derived.isEmpty ? "PDF 书籍" : derived
  }

  static func renderSize(for bounds: CGRect, limits: PdfImportLimits) throws -> CGSize {
    guard bounds.width.isFinite, bounds.height.isFinite,
      bounds.origin.x.isFinite, bounds.origin.y.isFinite,
      limits.maxImagePixels > 0, limits.maxImageDimension > 0
    else {
      throw PdfImportError.invalidPage(index: 0)
    }
    let page = bounds.standardized
    let width = Double(page.width)
    let height = Double(page.height)
    guard width.isFinite, height.isFinite, width > 0, height > 0 else {
      throw PdfImportError.invalidPage(index: 0)
    }
    let longestSide = max(width, height)
    let dimensionScale = min(1_800.0, Double(limits.maxImageDimension)) / longestSide
    let pixelScale = sqrt(Double(limits.maxImagePixels) / (width * height))
    let scale = min(2.0, dimensionScale, pixelScale)
    guard scale.isFinite, scale > 0 else {
      throw PdfImportError.invalidPage(index: 0)
    }
    let pixelWidth = max(1, Int((width * scale).rounded(.down)))
    let pixelHeight = max(1, Int((height * scale).rounded(.down)))
    guard pixelWidth <= limits.maxImageDimension,
      pixelHeight <= limits.maxImageDimension,
      pixelWidth <= limits.maxImagePixels / pixelHeight
    else {
      throw PdfImportError.invalidPage(index: 0)
    }
    return CGSize(width: pixelWidth, height: pixelHeight)
  }

  static func expandedBytes(for size: CGSize) -> Int {
    Int(size.width) * Int(size.height) * 4
  }

  static func checkedAdd(_ amount: Int, to total: Int, limit: Int) -> Int? {
    guard amount >= 0, total >= 0, limit >= 0, total <= limit,
      amount <= limit - total
    else {
      return nil
    }
    return total + amount
  }

  static func byteCountDescription(_ bytes: Int) -> String {
    if bytes >= 1024 * 1024, bytes % (1024 * 1024) == 0 {
      return "\(bytes / (1024 * 1024)) MiB"
    }
    return "\(bytes) 字节"
  }
}

final class PdfImportConverter {
  static var defaultStagingRoot: URL {
    URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("Wenku8Imports", isDirectory: true)
  }

  private let stagingRoot: URL
  private let limits: PdfImportLimits
  private let fileManager: FileManager

  init(
    stagingRoot: URL = PdfImportConverter.defaultStagingRoot,
    limits: PdfImportLimits = .default,
    fileManager: FileManager = .default
  ) {
    self.stagingRoot = stagingRoot
    self.limits = limits
    self.fileManager = fileManager
  }

  func convert(path: String, name: String) throws -> String {
    guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PdfImportError.badRequest
    }
    let source = URL(fileURLWithPath: path)
    let accessed = source.startAccessingSecurityScopedResource()
    defer { if accessed { source.stopAccessingSecurityScopedResource() } }
    guard fileManager.isReadableFile(atPath: source.path) else {
      throw PdfImportError.unreadable
    }
    let attributes: [FileAttributeKey: Any]
    do {
      attributes = try fileManager.attributesOfItem(atPath: source.path)
    } catch {
      throw PdfImportError.unreadable
    }
    guard let fileSize = (attributes[.size] as? NSNumber)?.int64Value, fileSize >= 0 else {
      throw PdfImportError.unreadable
    }
    guard fileSize <= Int64(limits.maxSourceBytes) else {
      throw PdfImportError.sourceTooLarge(limit: limits.maxSourceBytes)
    }
    guard let document = PDFDocument(url: source) else {
      throw PdfImportError.unreadable
    }
    guard !document.isEncrypted, !document.isLocked, document.allowsCopying else {
      throw PdfImportError.encrypted
    }
    guard document.pageCount > 0 else {
      throw PdfImportError.emptyDocument
    }
    guard document.pageCount <= limits.maxPages else {
      throw PdfImportError.tooManyPages(limit: limits.maxPages)
    }

    let jobDirectory = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
    var completed = false
    defer {
      if !completed { try? fileManager.removeItem(at: jobDirectory) }
    }
    do {
      try fileManager.createDirectory(at: jobDirectory, withIntermediateDirectories: true)
    } catch {
      throw PdfImportError.writeFailed
    }

    var pages: [[String: String]] = []
    pages.reserveCapacity(document.pageCount)
    var expandedBytes = 0
    var encodedImageBytes = 0
    var minimumOutputBytes = 0

    for index in 0..<document.pageCount {
      try autoreleasepool {
        guard let page = document.page(at: index) else {
          throw PdfImportError.renderFailed(index: index)
        }
        let bounds = page.bounds(for: .mediaBox)
        let imageSize: CGSize
        do {
          imageSize = try PdfImportSupport.renderSize(for: bounds, limits: limits)
        } catch {
          throw PdfImportError.invalidPage(index: index)
        }
        let pageExpandedBytes = PdfImportSupport.expandedBytes(for: imageSize)
        guard let updatedExpandedBytes = PdfImportSupport.checkedAdd(
          pageExpandedBytes, to: expandedBytes, limit: limits.maxExpandedBytes
        ) else {
          throw PdfImportError.expandedTooLarge(limit: limits.maxExpandedBytes)
        }

        let text = page.string ?? ""
        minimumOutputBytes = try reserveOutput(text.utf8.count, total: minimumOutputBytes)
        let pngData = try render(page, bounds: bounds.standardized, size: imageSize, index: index)
        guard pngData.count <= limits.maxImageBytes else {
          throw PdfImportError.imageTooLarge(index: index, limit: limits.maxImageBytes)
        }
        minimumOutputBytes = try reserveOutput(pngData.count, total: minimumOutputBytes)
        encodedImageBytes += pngData.count

        let imageURL = jobDirectory.appendingPathComponent(
          String(format: "page-%06d.png", index + 1))
        do {
          try pngData.write(to: imageURL, options: .atomic)
        } catch {
          throw PdfImportError.writeFailed
        }
        expandedBytes = updatedExpandedBytes
        pages.append([
          "title": "第 \(index + 1) 页",
          "text": text,
          "imagePath": imageURL.path,
        ])
      }
    }

    let manifest: [String: Any] = [
      "title": PdfImportSupport.title(name: name, source: source),
      "pages": pages,
    ]
    let manifestData: Data
    do {
      manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    } catch {
      throw PdfImportError.writeFailed
    }
    guard PdfImportSupport.checkedAdd(
      manifestData.count, to: encodedImageBytes, limit: limits.maxOutputBytes
    ) != nil else {
      throw PdfImportError.outputTooLarge(limit: limits.maxOutputBytes)
    }
    let manifestURL = jobDirectory.appendingPathComponent("manifest.json")
    do {
      try manifestData.write(to: manifestURL, options: .atomic)
    } catch {
      throw PdfImportError.writeFailed
    }
    completed = true
    return manifestURL.path
  }

  private func reserveOutput(_ amount: Int, total: Int) throws -> Int {
    guard let updated = PdfImportSupport.checkedAdd(
      amount, to: total, limit: limits.maxOutputBytes
    ) else {
      throw PdfImportError.outputTooLarge(limit: limits.maxOutputBytes)
    }
    return updated
  }

  private func render(
    _ page: PDFPage, bounds: CGRect, size: CGSize, index: Int
  ) throws -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let image = renderer.image { context in
      let output = CGRect(origin: .zero, size: size)
      context.cgContext.setFillColor(UIColor.white.cgColor)
      context.cgContext.fill(output)
      context.cgContext.saveGState()
      context.cgContext.interpolationQuality = .high
      context.cgContext.translateBy(x: 0, y: size.height)
      let scale = min(size.width / bounds.width, size.height / bounds.height)
      context.cgContext.scaleBy(x: scale, y: -scale)
      context.cgContext.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
      page.draw(with: .mediaBox, to: context.cgContext)
      context.cgContext.restoreGState()
    }
    guard let data = image.pngData() else {
      throw PdfImportError.renderFailed(index: index)
    }
    return data
  }
}

final class PdfImportPlugin: NSObject, FlutterPlugin {
  static let channelName = "org.mewx.wenku8/pdf_import"

  private enum Completion {
    case success(manifestPath: String)
    case failure(PdfImportError)
  }

  private let converter: PdfImportConverter
  private let workQueue: DispatchQueue

  override init() {
    converter = PdfImportConverter()
    workQueue = DispatchQueue(label: "org.mewx.wenku8.pdf-import", qos: .userInitiated)
    super.init()
  }

  init(converter: PdfImportConverter) {
    self.converter = converter
    workQueue = DispatchQueue(label: "org.mewx.wenku8.pdf-import.tests", qos: .userInitiated)
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(PdfImportPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "convert" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let arguments = call.arguments as? [String: Any],
      let path = arguments["path"] as? String
    else {
      Self.finish(.failure(.badRequest), result: result)
      return
    }
    let name = arguments["name"] as? String ?? ""
    workQueue.async { [converter] in
      do {
        let manifestPath = try converter.convert(path: path, name: name)
        Self.finish(.success(manifestPath: manifestPath), result: result)
      } catch let error as PdfImportError {
        Self.finish(.failure(error), result: result)
      } catch {
        Self.finish(.failure(.conversionFailed), result: result)
      }
    }
  }

  private static func finish(_ completion: Completion, result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      switch completion {
      case .success(let manifestPath):
        result(["manifestPath": manifestPath])
      case .failure(let error):
        result(FlutterError(code: error.code, message: error.message, details: nil))
      }
    }
  }
}
