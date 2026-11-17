import Flutter
import UIKit
import UniformTypeIdentifiers

final class BookDocumentsPlugin: NSObject, FlutterPlugin {
  private struct PendingPicker {
    let result: FlutterResult
    let returnsList: Bool
    let extensions: Set<String>
  }

  private static let bookExtensions: Set<String> = [
    "txt", "epub", "mobi", "azw", "azw3", "prc", "fb2", "pdf",
    "doc", "docx", "rtf", "html", "htm", "xhtml", "md", "markdown", "zip",
  ]
  private var pendingPicker: PendingPicker?
  private let syncDocuments = BookSyncDocuments()

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "org.mewx.wenku8/book_documents",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(BookDocumentsPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "pickBooks":
      pickDocuments(
        extensions: Self.bookExtensions,
        multiple: true,
        returnsList: true,
        result: result
      )
    case "pickBook":
      pickDocuments(
        extensions: Self.bookExtensions,
        multiple: false,
        returnsList: false,
        result: result
      )
    case "pickImage":
      pickDocuments(
        extensions: ["png", "jpg", "jpeg", "webp", "gif"],
        multiple: false,
        returnsList: false,
        result: result
      )
    case "pickFont":
      pickDocuments(
        extensions: ["ttf", "otf"],
        multiple: false,
        returnsList: false,
        result: result
      )
    case "decodeText", "decodeTextFile":
      decodeText(
        arguments,
        toFile: call.method == "decodeTextFile",
        result: result
      )
    case "openSync", "createSync":
      guard pendingPicker == nil else {
        result(FlutterError(code: "busy", message: "请先完成当前文件选择", details: nil))
        return
      }
      syncDocuments.choose(create: call.method == "createSync", result: result)
    case "syncInfo":
      syncDocuments.background(result) { [syncDocuments] in syncDocuments.info() }
    case "readSync":
      syncDocuments.background(result) { [syncDocuments] in try syncDocuments.read() }
    case "writeSync":
      syncDocuments.background(result) { [syncDocuments] in
        try syncDocuments.write(arguments: arguments)
        return true
      }
    case "disconnectSync":
      syncDocuments.disconnect()
      result(nil)
    case "recoverSync":
      syncDocuments.background(result) { [syncDocuments] in
        try syncDocuments.recover(which: arguments?["which"] as? String)
      }
    case "releaseBooks":
      releaseBooks(arguments, result: result)
    case "scanFolderInfo", "pendingBookOpen":
      result(nil)
    case "prepareBook":
      result([[
        "name": arguments?["name"] as? String ?? "书籍",
        "error": "此格式需要由应用内文档转换模块处理",
      ]])
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private var stagingDirectory: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "Wenku8Imports",
      isDirectory: true
    )
  }

  private func pickDocuments(
    extensions: Set<String>,
    multiple: Bool,
    returnsList: Bool,
    result: @escaping FlutterResult
  ) {
    guard pendingPicker == nil, !syncDocuments.isBusy else {
      result(FlutterError(code: "PICKER_BUSY", message: "已有文件选择操作正在进行", details: nil))
      return
    }
    guard let presenter = Self.topViewController() else {
      result(FlutterError(code: "NO_UI", message: "暂时无法打开系统文件选择器", details: nil))
      return
    }
    let ordered = extensions.sorted()
    var types = ordered.compactMap { UTType(filenameExtension: $0) }
    if types.count != ordered.count {
      types.append(.data)
    }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
    picker.allowsMultipleSelection = multiple
    picker.delegate = self
    pendingPicker = PendingPicker(
      result: result,
      returnsList: returnsList,
      extensions: extensions
    )
    presenter.present(picker, animated: true)
  }

  private func stage(_ source: URL, allowedExtensions: Set<String>) throws -> [String: Any] {
    let ext = source.pathExtension.lowercased()
    guard allowedExtensions.contains(ext) else {
      throw NSError(
        domain: "Wenku8Documents",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "请选择支持的电子书或文档格式"]
      )
    }
    let accessed = source.startAccessingSecurityScopedResource()
    defer { if accessed { source.stopAccessingSecurityScopedResource() } }
    try FileManager.default.createDirectory(
      at: stagingDirectory,
      withIntermediateDirectories: true
    )
    let destination = stagingDirectory.appendingPathComponent(
      UUID().uuidString + "." + ext
    )
    do {
      try FileManager.default.copyItem(at: source, to: destination)
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
    return ["name": source.lastPathComponent, "path": destination.path]
  }

  private func decodeText(
    _ arguments: [String: Any]?,
    toFile: Bool,
    result: @escaping FlutterResult
  ) {
    guard let path = arguments?["path"] as? String else {
      result(FlutterError(code: "BAD_PATH", message: "缺少书籍文件路径", details: nil))
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      func finish(_ value: Any?) {
        DispatchQueue.main.async { result(value) }
      }
      do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
        guard data.count <= 128 * 1024 * 1024 else {
          throw NSError(
            domain: "Wenku8Documents",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "单本 TXT 不能超过 128 MiB"]
          )
        }
        let requested = (arguments?["encoding"] as? String ?? "auto").lowercased()
        let text = try Self.decode(data, requested: requested)
        if toFile {
          try FileManager.default.createDirectory(
            at: self.stagingDirectory,
            withIntermediateDirectories: true
          )
          let output = self.stagingDirectory.appendingPathComponent(UUID().uuidString + ".txt")
          guard let encoded = text.data(using: .utf8) else {
            throw NSError(
              domain: "Wenku8Documents",
              code: 4,
              userInfo: [NSLocalizedDescriptionKey: "文本无法转换为 UTF-8"]
            )
          }
          try encoded.write(to: output, options: .atomic)
          finish(output.path)
        } else {
          finish(text)
        }
      } catch {
        finish(FlutterError(code: "DECODE_FAILED", message: error.localizedDescription, details: nil))
      }
    }
  }

  private static func decode(_ data: Data, requested: String) throws -> String {
    let gb18030 = String.Encoding(
      rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    let big5 = String.Encoding(
      rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.big5.rawValue)))
    let big5HKSCS = String.Encoding(
      rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.big5_HKSCS_1999.rawValue)))
    let named: [String: String.Encoding] = [
      "utf-8": .utf8, "gb18030": gb18030, "gbk": gb18030,
      "big5": big5, "big5-hkscs": big5HKSCS,
      "utf-16le": .utf16LittleEndian, "utf-16be": .utf16BigEndian,
    ]
    let encodings: [String.Encoding]
    if let encoding = named[requested] {
      encodings = [encoding]
    } else {
      var automatic: [String.Encoding] = [.utf8, gb18030, big5, big5HKSCS]
      if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
        automatic.insert(.utf16, at: 0)
      }
      encodings = automatic
    }
    for encoding in encodings {
      if let text = String(data: data, encoding: encoding) { return text }
    }
    throw NSError(
      domain: "Wenku8Documents",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "无法识别 TXT 编码，请在导入设置中手动选择"])
  }

  private func releaseBooks(_ arguments: [String: Any]?, result: @escaping FlutterResult) {
    let paths = arguments?["paths"] as? [String] ?? []
    let root = stagingDirectory.standardizedFileURL.path + "/"
    for path in paths {
      let url = URL(fileURLWithPath: path).standardizedFileURL
      if url.path.hasPrefix(root) {
        try? FileManager.default.removeItem(at: url)
      }
    }
    result(nil)
  }

  static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    var controller = window?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    if let navigation = controller as? UINavigationController {
      return navigation.visibleViewController
    }
    if let tab = controller as? UITabBarController {
      return tab.selectedViewController
    }
    return controller
  }
}

extension BookDocumentsPlugin: UIDocumentPickerDelegate {
  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let pending = pendingPicker else { return }
    pendingPicker = nil
    var selections: [[String: Any]] = []
    for url in urls {
      do {
        selections.append(try stage(url, allowedExtensions: pending.extensions))
      } catch {
        selections.append([
          "name": url.lastPathComponent,
          "error": error.localizedDescription,
        ])
      }
    }
    if pending.returnsList {
      pending.result(selections)
    } else if let selection = selections.first {
      if let message = selection["error"] as? String {
        pending.result(FlutterError(code: "IMPORT_FAILED", message: message, details: nil))
      } else {
        pending.result(selection)
      }
    } else {
      pending.result(nil)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard let pending = pendingPicker else { return }
    pendingPicker = nil
    if pending.returnsList {
      pending.result([[String: Any]]())
    } else {
      pending.result(nil)
    }
  }
}
