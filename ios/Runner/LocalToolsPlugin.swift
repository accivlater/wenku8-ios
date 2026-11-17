import Flutter
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

private enum LocalToolError: Error {
  case input
  case busy
  case noUI
  case permission
}

final class LocalToolsPlugin: NSObject, FlutterPlugin {
  private enum PendingKind {
    case importBackup
    case exportBackup
    case exportImage
    case share
    case photo
  }

  private struct PendingOperation {
    let id = UUID()
    let kind: PendingKind
    let result: FlutterResult
    let temporaryURL: URL?
  }

  private static let maximumBackupBytes = 4 * 1024 * 1024
  private static let maximumImageBytes = 20 * 1024 * 1024
  private var pending: PendingOperation?
  private var requestedKeepScreenOn = false
  private var suspended = false
  private var observers: [NSObjectProtocol] = []

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = LocalToolsPlugin()
    let channel = FlutterMethodChannel(
      name: "org.mewx.wenku8/local_tools",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.observeLifecycle()
    LocalReaderControlsPlugin.register(with: registrar)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "flushPreferences":
      result(UserDefaults.standard.synchronize())
    case "getKeepScreenOn":
      result(UIApplication.shared.isIdleTimerDisabled)
    case "keepScreenOn":
      guard let enabled = (call.arguments as? NSNumber)?.boolValue else {
        result(FlutterError(code: "input", message: "亮屏参数无效", details: nil))
        return
      }
      requestedKeepScreenOn = enabled
      UIApplication.shared.isIdleTimerDisabled = enabled && !suspended
      result(nil)
    case "exportBackup":
      guard let text = arguments?["text"] as? String,
        let data = text.data(using: .utf8),
        data.count <= Self.maximumBackupBytes
      else {
        result(FlutterError(code: "size", message: "备份为空或超过 4 MiB", details: nil))
        return
      }
      let name = safeName(arguments?["name"] as? String, fallback: "wenku8-backup.json")
      do {
        let url = try writeTemporary(data, name: name)
        presentExport(url, kind: .exportBackup, result: result)
      } catch {
        result(FlutterError(code: "document", message: "备份文件未能准备", details: nil))
      }
    case "importBackup":
      presentBackupImport(result)
    case "shareText":
      guard let text = arguments?["text"] as? String,
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        text.count <= 10000
      else {
        result(FlutterError(code: "input", message: "分享文字为空或过长", details: nil))
        return
      }
      presentShare([text], result: result)
    case "shareImage", "exportImage", "saveBookImage":
      do {
        let image = try imageData(arguments)
        if call.method == "saveBookImage" {
          savePhoto(image, result: result)
        } else {
          let url = try writeTemporary(image.data, name: image.name)
          if call.method == "shareImage" {
            presentShare([url], temporaryURL: url, result: result)
          } else {
            presentExport(url, kind: .exportImage, result: result)
          }
        }
      } catch {
        result(FlutterError(code: "image", message: "图片格式、大小或文件名无效", details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func safeName(_ proposed: String?, fallback: String) -> String {
    var name = (proposed ?? fallback)
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: "\\", with: "-")
      .replacingOccurrences(of: ":", with: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty || name == "." || name == ".." {
      name = fallback
    }
    return String(name.prefix(120))
  }

  private func writeTemporary(_ data: Data, name: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("Wenku8LocalTools", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appendingPathComponent(name)
      try data.write(to: url, options: .atomic)
      return url
    } catch {
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
  }

  private func imageData(_ arguments: [String: Any]?) throws -> (data: Data, name: String) {
    guard let typed = arguments?["bytes"] as? FlutterStandardTypedData else {
      throw LocalToolError.input
    }
    let data = typed.data
    guard !data.isEmpty, data.count <= Self.maximumImageBytes,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetCount(source) > 0,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
      let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
      width.int64Value > 0, height.int64Value > 0,
      width.int64Value <= 20000, height.int64Value <= 20000,
      width.int64Value * height.int64Value <= 80000000,
      let identifier = CGImageSourceGetType(source) as String?
    else {
      throw LocalToolError.input
    }
    let ext: String
    switch identifier {
    case UTType.png.identifier:
      ext = "png"
    case UTType.jpeg.identifier:
      ext = "jpg"
    case UTType.gif.identifier:
      ext = "gif"
    case UTType.webP.identifier:
      ext = "webp"
    case UTType.heic.identifier:
      ext = "heic"
    default:
      throw LocalToolError.input
    }
    var name = safeName(arguments?["name"] as? String, fallback: "wenku8-image")
    if URL(fileURLWithPath: name).pathExtension.isEmpty {
      name += "." + ext
    }
    return (data, name)
  }

  private func begin(_ kind: PendingKind, result: @escaping FlutterResult, temporaryURL: URL?) throws -> PendingOperation {
    guard pending == nil else { throw LocalToolError.busy }
    let operation = PendingOperation(kind: kind, result: result, temporaryURL: temporaryURL)
    pending = operation
    return operation
  }

  private func presentBackupImport(_ result: @escaping FlutterResult) {
    var operation: PendingOperation?
    do {
      operation = try begin(.importBackup, result: result, temporaryURL: nil)
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .plainText, .data])
      picker.allowsMultipleSelection = false
      picker.delegate = self
      try presenter().present(picker, animated: true)
    } catch {
      if let operation {
        finish(id: operation.id) { _ in }
      }
      result(FlutterError(code: "document", message: "暂时无法打开备份选择器", details: nil))
    }
  }

  private func presentExport(_ url: URL, kind: PendingKind, result: @escaping FlutterResult) {
    var operation: PendingOperation?
    do {
      operation = try begin(kind, result: result, temporaryURL: url)
      let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
      picker.delegate = self
      try presenter().present(picker, animated: true)
    } catch {
      if let operation {
        finish(id: operation.id) { _ in }
      } else {
        cleanup(url)
      }
      result(FlutterError(code: "document", message: "暂时无法打开文件导出面板", details: nil))
    }
  }

  private func presentShare(_ items: [Any], temporaryURL: URL? = nil, result: @escaping FlutterResult) {
    var created: PendingOperation?
    do {
      let operation = try begin(.share, result: result, temporaryURL: temporaryURL)
      created = operation
      let presenter = try presenter()
      let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
      configurePopover(controller, presenter: presenter)
      controller.completionWithItemsHandler = { [weak self] _, completed, _, activityError in
        self?.finish(id: operation.id) { current in
          if let activityError {
            current.result(FlutterError(code: "share", message: activityError.localizedDescription, details: nil))
          } else if completed {
            current.result(nil)
          } else {
            current.result(FlutterError(code: "SHARE_CANCELLED", message: "已取消分享", details: nil))
          }
        }
      }
      presenter.present(controller, animated: true)
    } catch {
      if let created {
        finish(id: created.id) { _ in }
      } else {
        cleanup(temporaryURL)
      }
      result(FlutterError(code: "share", message: "系统分享面板未能打开", details: nil))
    }
  }

  private func savePhoto(_ image: (data: Data, name: String), result: @escaping FlutterResult) {
    do {
      let operation = try begin(.photo, result: result, temporaryURL: nil)
      let save = { [weak self] in
        PHPhotoLibrary.shared().performChanges({
          let request = PHAssetCreationRequest.forAsset()
          let options = PHAssetResourceCreationOptions()
          options.originalFilename = image.name
          request.addResource(with: .photo, data: image.data, options: options)
        }) { success, error in
          DispatchQueue.main.async {
            self?.finish(id: operation.id) { operation in
              if success {
                operation.result(true)
              } else {
                operation.result(FlutterError(
                  code: "image",
                  message: error?.localizedDescription ?? "图片未能写入照片图库",
                  details: nil
                ))
              }
            }
          }
        }
      }
      let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
      if status == .notDetermined {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { next in
          DispatchQueue.main.async {
            if next == .authorized || next == .limited {
              save()
            } else {
              self.finish(id: operation.id) { operation in
                operation.result(FlutterError(
                  code: "PHOTO_PERMISSION",
                  message: "请允许添加照片，或改用导出到文件",
                  details: nil
                ))
              }
            }
          }
        }
      } else if status == .authorized || status == .limited {
        save()
      } else {
        finish(id: operation.id) { operation in
          operation.result(FlutterError(
            code: "PHOTO_PERMISSION",
            message: "请允许添加照片，或改用导出到文件",
            details: nil
          ))
        }
      }
    } catch {
      result(FlutterError(code: "busy", message: "已有文件或分享操作正在进行", details: nil))
    }
  }

  private func finish(id: UUID, completion: (PendingOperation) -> Void) {
    guard let operation = pending, operation.id == id else { return }
    pending = nil
    completion(operation)
    cleanup(operation.temporaryURL)
  }

  private func cleanup(_ url: URL?) {
    guard let url else { return }
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
  }

  private func presenter() throws -> UIViewController {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
    var controller = window?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    if let navigation = controller as? UINavigationController {
      controller = navigation.visibleViewController
    }
    if let tab = controller as? UITabBarController {
      controller = tab.selectedViewController
    }
    guard let controller else { throw LocalToolError.noUI }
    return controller
  }

  private func configurePopover(
    _ controller: UIActivityViewController,
    presenter: UIViewController
  ) {
    guard let popover = controller.popoverPresentationController else { return }
    let view = presenter.view!
    popover.sourceView = view
    popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
    popover.permittedArrowDirections = []
    popover.canOverlapSourceViewRect = true
  }

  private func observeLifecycle() {
    let center = NotificationCenter.default
    observers.append(center.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.suspended = true
      UIApplication.shared.isIdleTimerDisabled = false
    })
    observers.append(center.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      self.suspended = false
      UIApplication.shared.isIdleTimerDisabled = self.requestedKeepScreenOn
    })
  }

  deinit {
    UIApplication.shared.isIdleTimerDisabled = false
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    if let operation = pending {
      pending = nil
      operation.result(FlutterError(code: "closed", message: "文件或分享操作已关闭", details: nil))
      cleanup(operation.temporaryURL)
    }
  }
}

extension LocalToolsPlugin: UIDocumentPickerDelegate {
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let operation = pending else { return }
    switch operation.kind {
    case .importBackup:
      guard let url = urls.first else {
        finish(id: operation.id) { $0.result(nil) }
        return
      }
      do {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: LocalToolsPlugin.maximumBackupBytes + 1) ?? Data()
        guard data.count <= LocalToolsPlugin.maximumBackupBytes,
          let text = String(data: data, encoding: .utf8)
        else {
          throw LocalToolError.input
        }
        finish(id: operation.id) { $0.result(text) }
      } catch {
        finish(id: operation.id) {
          $0.result(FlutterError(code: "document", message: "备份不是有效的 UTF-8 JSON 文件或超过 4 MiB", details: nil))
        }
      }
    case .exportBackup, .exportImage:
      finish(id: operation.id) { $0.result(!urls.isEmpty) }
    case .share, .photo:
      break
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard let operation = pending else { return }
    finish(id: operation.id) { operation in
      switch operation.kind {
      case .importBackup:
        operation.result(nil)
      case .exportBackup, .exportImage:
        operation.result(false)
      case .share, .photo:
        break
      }
    }
  }
}

private final class LocalReaderControlsPlugin: NSObject, FlutterPlugin {
  private var readerActive = false
  private var suspended = false
  private var requestedBrightness: CGFloat?
  private var savedBrightness: CGFloat?
  private var observers: [NSObjectProtocol] = []

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = LocalReaderControlsPlugin()
    let channel = FlutterMethodChannel(
      name: "org.mewx.wenku8/reader_controls",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.observeLifecycle()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "brightness":
      result(Double(UIScreen.main.brightness))
    case "apply":
      let arguments = call.arguments as? [String: Any]
      let brightness = arguments?["brightness"] as? NSNumber
      if let brightness,
        !brightness.doubleValue.isFinite || brightness.doubleValue < 0 || brightness.doubleValue > 1
      {
        result(FlutterError(code: "brightness", message: "阅读亮度超出范围", details: nil))
        return
      }
      let active: Bool
      if let value = arguments?["active"] as? NSNumber {
        active = value.boolValue
      } else {
        active = brightness != nil
      }
      apply(active: active, brightness: brightness.map { CGFloat($0.doubleValue) })
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func apply(active: Bool, brightness: CGFloat?) {
    readerActive = active
    requestedBrightness = active ? brightness : nil
    guard active, let brightness else {
      restoreBrightness()
      return
    }
    guard !suspended else { return }
    if savedBrightness == nil {
      savedBrightness = UIScreen.main.brightness
    }
    UIScreen.main.brightness = brightness
  }

  private func restoreBrightness() {
    guard let savedBrightness else { return }
    UIScreen.main.brightness = savedBrightness
    self.savedBrightness = nil
  }

  private func observeLifecycle() {
    let center = NotificationCenter.default
    observers.append(center.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.suspended = true
      self?.restoreBrightness()
    })
    observers.append(center.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      self.suspended = false
      self.apply(active: self.readerActive, brightness: self.requestedBrightness)
    })
  }

  deinit {
    restoreBrightness()
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
  }
}
