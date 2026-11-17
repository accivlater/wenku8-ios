import Flutter
import UIKit
import UniformTypeIdentifiers

private struct BookSyncFailure: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}

final class BookSyncDocuments: NSObject {
  private static let bookmarkKey = "Wenku8BookSyncBookmarkV1"
  private static let createdKey = "Wenku8BookSyncCreatedV1"
  private static let maximumBytes = 256 * 1024 * 1024
  private let defaults = UserDefaults.standard
  private let files = FileManager.default
  private var pending: FlutterResult?
  private var pendingCreate = false

  private var staging: URL {
    files.temporaryDirectory.appendingPathComponent("Wenku8Sync", isDirectory: true)
  }

  private var recovery: URL {
    let root = files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return root.appendingPathComponent("sync-recovery", isDirectory: true)
  }

  var isBusy: Bool { pending != nil }

  func choose(create: Bool, result: @escaping FlutterResult) {
    guard pending == nil else {
      result(FlutterError(code: "busy", message: "请先完成当前云文档选择", details: nil))
      return
    }
    guard let presenter = BookDocumentsPlugin.topViewController() else {
      result(FlutterError(code: "NO_UI", message: "暂时无法打开系统文件选择器", details: nil))
      return
    }
    do {
      try files.createDirectory(at: staging, withIntermediateDirectories: true)
      let placeholder = staging.appendingPathComponent("轻小说文库.wenku8sync")
      if create { try Data().write(to: placeholder, options: .atomic) }
      let picker: UIDocumentPickerViewController
      if create {
        picker = UIDocumentPickerViewController(forExporting: [placeholder])
      } else {
        let type = UTType(filenameExtension: "wenku8sync") ?? .data
        picker = UIDocumentPickerViewController(forOpeningContentTypes: [type])
      }
      picker.delegate = self
      pendingCreate = create
      pending = result
      presenter.present(picker, animated: true)
    } catch {
      pending = nil
      result(FlutterError(code: "document", message: error.localizedDescription, details: nil))
    }
  }

  func info() -> [String: Any]? {
    guard let data = defaults.data(forKey: Self.bookmarkKey),
      let url = try? resolve(data)
    else { return nil }
    return [
      "name": url.lastPathComponent,
      "authority": url.host ?? "iCloud / Files",
      "created": defaults.bool(forKey: Self.createdKey),
    ]
  }

  func select(_ url: URL, created: Bool) throws {
    let bookmark = try url.bookmarkData(options: [])
    defaults.set(bookmark, forKey: Self.bookmarkKey)
    defaults.set(created, forKey: Self.createdKey)
  }

  func read() throws -> [String: Any] {
    let url = try selected()
    try files.createDirectory(at: staging, withIntermediateDirectories: true)
    let before = staging.appendingPathComponent("cloud-before.wenku8sync")
    let data = try readData(url)
    try data.write(to: before, options: .atomic)
    return [
      "path": before.path,
      "size": data.count,
      "outputPath": staging.appendingPathComponent("cloud-next.wenku8sync").path,
    ]
  }

  func write(arguments: [String: Any]?) throws {
    guard let nextPath = arguments?["path"] as? String,
      let beforePath = arguments?["expectedPath"] as? String
    else { throw BookSyncFailure(message: "同步文件参数不完整") }
    let next = URL(fileURLWithPath: nextPath).standardizedFileURL
    let before = URL(fileURLWithPath: beforePath).standardizedFileURL
    let root = staging.standardizedFileURL.path + "/"
    guard next.path.hasPrefix(root), before.path.hasPrefix(root) else {
      throw BookSyncFailure(message: "同步暂存路径无效")
    }
    let nextData = try readData(next)
    guard !nextData.isEmpty else { throw BookSyncFailure(message: "同步文件为空") }
    let beforeData = try readData(before)
    let target = try selected()
    let fresh = try readData(target)
    guard fresh == beforeData else {
      throw BookSyncFailure(message: "云端文件已发生变化，请重新同步")
    }
    try files.createDirectory(at: recovery, withIntermediateDirectories: true)
    try beforeData.write(
      to: recovery.appendingPathComponent("cloud-before.wenku8sync"), options: .atomic)
    try nextData.write(
      to: recovery.appendingPathComponent("cloud-next.wenku8sync"), options: .atomic)
    try withAccess(to: target) {
      let handle = try FileHandle(forWritingTo: $0)
      do {
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: nextData)
        try handle.synchronize()
        try handle.close()
      } catch {
        try? handle.close()
        throw error
      }
    }
    guard try readData(target) == nextData else {
      throw BookSyncFailure(message: "云端写入未完整确认，恢复副本已保留")
    }
    defaults.set(false, forKey: Self.createdKey)
  }

  func disconnect() {
    defaults.removeObject(forKey: Self.bookmarkKey)
    defaults.removeObject(forKey: Self.createdKey)
  }

  func recover(which: String?) throws -> String? {
    guard which == "before" || which == "next" else {
      throw BookSyncFailure(message: "同步恢复类型无效")
    }
    let source = recovery.appendingPathComponent("cloud-\(which!).wenku8sync")
    guard files.fileExists(atPath: source.path) else { return nil }
    try files.createDirectory(at: staging, withIntermediateDirectories: true)
    let target = staging.appendingPathComponent("recovery-\(which!).wenku8sync")
    try readData(source).write(to: target, options: .atomic)
    return target.path
  }

  func background(_ result: @escaping FlutterResult, work: @escaping () throws -> Any?) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let value = try work()
        DispatchQueue.main.async { result(value) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "document", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func selected() throws -> URL {
    guard let data = defaults.data(forKey: Self.bookmarkKey) else {
      throw BookSyncFailure(message: "请先选择云同步文件")
    }
    return try resolve(data)
  }

  private func resolve(_ data: Data) throws -> URL {
    var stale = false
    let url = try URL(
      resolvingBookmarkData: data,
      options: [],
      bookmarkDataIsStale: &stale
    )
    if stale {
      defaults.set(try url.bookmarkData(options: []), forKey: Self.bookmarkKey)
    }
    return url
  }

  private func readData(_ url: URL) throws -> Data {
    try withAccess(to: url) {
      let attributes = try files.attributesOfItem(atPath: $0.path)
      let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
      guard size >= 0, size <= Self.maximumBytes else {
        throw BookSyncFailure(message: "同步文件超过 256 MiB 限制")
      }
      return try Data(contentsOf: $0, options: .mappedIfSafe)
    }
  }

  private func withAccess<T>(to url: URL, work: (URL) throws -> T) throws -> T {
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    return try work(url)
  }
}

extension BookSyncDocuments: UIDocumentPickerDelegate {
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = pending else { return }
    pending = nil
    guard let url = urls.first else { result(nil); return }
    do {
      try select(url, created: pendingCreate)
      result(info())
    } catch {
      result(FlutterError(code: "document", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard let result = pending else { return }
    pending = nil
    result(nil)
  }
}
