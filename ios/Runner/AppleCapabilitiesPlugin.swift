import AppIntents
import CoreSpotlight
import Flutter
import Intents
import UIKit
import UniformTypeIdentifiers

final class AppleCapabilitiesPlugin: NSObject, FlutterPlugin {
  private static let channelName = "org.mewx.wenku8/apple_capabilities"
  private static let openBookActivity = "org.mewx.wenku8.open-book"
  private static let continueReadingActivity = "org.mewx.wenku8.continue-reading"
  private static let searchBooksActivity = "org.mewx.wenku8.search-books"
  private static let startListeningActivity = "org.mewx.wenku8.start-listening"
  private static let pauseListeningActivity = "org.mewx.wenku8.pause-listening"
  private static let spotlightDomain = "org.mewx.wenku8.books"
  private static let spotlightDefaultsKey = "AppleCapabilitiesSpotlightV1"
  private static let dedupWindow: TimeInterval = 15

  private static var channel: FlutterMethodChannel?
  private static var dartReady = false
  private static var pendingActions: [[String: Any]] = []
  private static var pendingIDs = Set<String>()
  private static var recentActions: [String: Date] = [:]
  private static var inFlightAction: [String: Any]?
  private static var deliveryGeneration = 0

  static func register(with registrar: FlutterPluginRegistrar) {
    requeueInFlight()
    dartReady = false
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    self.channel = channel
    registrar.addMethodCallDelegate(AppleCapabilitiesPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "activate":
      Self.requeueInFlight()
      Self.dartReady = true
      let pending = Self.pendingActions
      Self.pendingActions.removeAll()
      Self.pendingIDs.removeAll()
      result(pending)
    case "deactivate":
      Self.dartReady = false
      Self.requeueInFlight()
      result(nil)
    case "indexBooks":
      Self.indexBooks(arguments, result: result)
    case "removeIndexes":
      Self.removeIndexes(arguments, result: result)
    case "removeAllIndexes":
      Self.removeAllIndexes(result: result)
    case "indexedBookIDs":
      let ids = Self.spotlightPayloads().keys.compactMap { identifier in
        identifier.hasPrefix("book.") ? Int(identifier.dropFirst("book.".count)) : nil
      }.sorted()
      result(ids)
    case "donateActions":
      Self.donateActions(arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static func handle(_ activity: NSUserActivity) -> Bool {
    guard var action = actionPayload(for: activity), let id = action["id"] as? String else {
      return false
    }
    action["id"] = id
    if Thread.isMainThread {
      enqueue(action)
    } else {
      DispatchQueue.main.sync { enqueue(action) }
    }
    return true
  }

  static func performShortcut(action: String, query: String? = nil) {
    let activity = donatedActivity(
      action: action,
      title: shortcutTitle(for: action),
      phrase: nil,
      query: query
    )
    if Thread.isMainThread {
      activity.becomeCurrent()
    } else {
      DispatchQueue.main.async { activity.becomeCurrent() }
    }
    _ = handle(activity)
  }

  private static func actionPayload(for activity: NSUserActivity) -> [String: Any]? {
    if activity.activityType == CSSearchableItemActionType {
      guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
        return nil
      }
      var payload = spotlightPayloads()[identifier]
      if payload == nil, identifier.hasPrefix("book."),
         let bookID = Int(identifier.dropFirst("book.".count)) {
        payload = ["action": "openBook", "bookId": bookID]
      }
      guard var action = payload, action["action"] as? String == "openBook" else {
        return nil
      }
      let event = action["eventId"] as? String ?? identifier
      action["id"] = "spotlight:\(identifier):\(event)"
      return action
    }

    let expectedAction: String
    switch activity.activityType {
    case openBookActivity: expectedAction = "openBook"
    case continueReadingActivity: expectedAction = "continueReading"
    case searchBooksActivity: expectedAction = "searchBooks"
    case startListeningActivity: expectedAction = "startListening"
    case pauseListeningActivity: expectedAction = "pauseListening"
    default: return nil
    }
    guard var action = activity.userInfo as? [String: Any],
          action["action"] as? String == expectedAction else {
      return nil
    }
    if expectedAction == "openBook" {
      guard let bookID = action["bookId"] as? Int, bookID > 0 else { return nil }
    }
    let event = action["eventId"] as? String ?? activity.persistentIdentifier ?? UUID().uuidString
    action["id"] = "activity:\(activity.activityType):\(event)"
    return action
  }

  private static func enqueue(_ action: [String: Any]) {
    guard let id = action["id"] as? String else { return }
    let now = Date()
    recentActions = recentActions.filter {
      now.timeIntervalSince($0.value) < dedupWindow
    }
    if pendingIDs.contains(id) || inFlightAction?["id"] as? String == id ||
        recentActions[id] != nil {
      return
    }
    recentActions[id] = now
    if recentActions.count > 128, let oldest = recentActions.min(by: { $0.value < $1.value })?.key {
      recentActions.removeValue(forKey: oldest)
    }
    pendingIDs.insert(id)
    pendingActions.append(action)
    deliverNext()
  }

  private static func deliverNext() {
    guard dartReady, let channel, inFlightAction == nil, !pendingActions.isEmpty else {
      return
    }
    let action = pendingActions.removeFirst()
    let id = action["id"] as? String ?? ""
    let generation = deliveryGeneration
    inFlightAction = action
    channel.invokeMethod("performAction", arguments: action) { response in
      DispatchQueue.main.async {
        guard generation == deliveryGeneration else { return }
        inFlightAction = nil
        pendingIDs.remove(id)
        if let error = response as? FlutterError {
          pendingActions.insert(action, at: 0)
          pendingIDs.insert(id)
          dartReady = false
          NSLog("Apple capability action deferred: \(error.message ?? error.code)")
          return
        }
        if response as? String == "cancelled" {
          recentActions.removeValue(forKey: id)
        }
        deliverNext()
      }
    }
  }

  private static func requeueInFlight() {
    deliveryGeneration += 1
    guard let action = inFlightAction else { return }
    inFlightAction = nil
    let id = action["id"] as? String ?? ""
    if !pendingIDs.contains(id) {
      pendingActions.insert(action, at: 0)
      pendingIDs.insert(id)
    }
  }

  private static func indexBooks(
    _ arguments: [String: Any]?,
    result: @escaping FlutterResult
  ) {
    guard let rawBooks = arguments?["books"] as? [Any], !rawBooks.isEmpty else {
      result(FlutterError(code: "BAD_BOOKS", message: "书籍索引为空或格式不正确", details: nil))
      return
    }
    var items: [CSSearchableItem] = []
    var newPayloads: [String: [String: Any]] = [:]
    for case let rawBook as [String: Any] in rawBooks {
      guard let bookID = rawBook["bookId"] as? Int, bookID > 0,
            let rawTitle = rawBook["title"] as? String else {
        result(FlutterError(code: "BAD_BOOK", message: "书籍索引缺少有效 ID 或书名", details: nil))
        return
      }
      let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      if title.isEmpty {
        result(FlutterError(code: "BAD_BOOK", message: "书名不能为空", details: nil))
        return
      }
      let author = (rawBook["author"] as? String ?? "").trimmingCharacters(
        in: .whitespacesAndNewlines)
      let chapterTitle = rawBook["chapterTitle"] as? String
      let position = normalizedPosition(rawBook["position"])
      if rawBook["position"] != nil && !(rawBook["position"] is NSNull) && position == nil {
        result(FlutterError(code: "BAD_POSITION", message: "阅读进度格式不正确", details: nil))
        return
      }
      let identifier = "book.\(bookID)"
      let eventID = UUID().uuidString
      var payload: [String: Any] = [
        "action": "openBook",
        "bookId": bookID,
        "eventId": eventID,
      ]
      if let position { payload["position"] = position }
      newPayloads[identifier] = payload

      let attributes = CSSearchableItemAttributeSet(contentType: UTType.content)
      attributes.title = title
      attributes.displayName = title
      var description = [author, chapterTitle ?? ""].filter { !$0.isEmpty }
      if let fraction = position?["fraction"] as? Double {
        description.append("本章已读 \(Int((fraction * 100).rounded()))%")
      }
      attributes.contentDescription = description.joined(separator: " · ")
      let suppliedKeywords = rawBook["keywords"] as? [String] ?? []
      attributes.keywords = Array(Set(
        [title, author, chapterTitle ?? ""] + suppliedKeywords
      )).filter { !$0.isEmpty }.sorted()
      attributes.relatedUniqueIdentifier = identifier
      items.append(CSSearchableItem(
        uniqueIdentifier: identifier,
        domainIdentifier: spotlightDomain,
        attributeSet: attributes
      ))
    }
    if items.count != rawBooks.count {
      result(FlutterError(code: "BAD_BOOKS", message: "书籍索引格式不正确", details: nil))
      return
    }
    var stored = spotlightPayloads()
    for (identifier, payload) in newPayloads { stored[identifier] = payload }
    saveSpotlightPayloads(stored)
    CSSearchableIndex.default().indexSearchableItems(items) { error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(
            code: "SPOTLIGHT_INDEX_FAILED",
            message: error.localizedDescription,
            details: nil
          ))
        } else {
          result(nil)
        }
      }
    }
  }

  private static func normalizedPosition(_ value: Any?) -> [String: Any]? {
    guard let source = value as? [String: Any] else { return nil }
    var position: [String: Any] = [:]
    for key in ["chapter", "chapterId", "paragraphIndex", "textOffset", "updatedAt"] {
      if let number = source[key] as? NSNumber {
        guard number.doubleValue.isFinite else { return nil }
        position[key] = number.int64Value
      }
    }
    for key in ["offset", "fraction", "paragraphFraction"] {
      if let number = source[key] as? NSNumber {
        guard number.doubleValue.isFinite else { return nil }
        position[key] = number.doubleValue
      }
    }
    return position
  }

  private static func removeIndexes(
    _ arguments: [String: Any]?,
    result: @escaping FlutterResult
  ) {
    guard let bookIDs = arguments?["bookIds"] as? [Int] else {
      result(FlutterError(code: "BAD_BOOKS", message: "缺少要移除的书籍 ID", details: nil))
      return
    }
    let identifiers = bookIDs.map { "book.\($0)" }
    var stored = spotlightPayloads()
    for identifier in identifiers { stored.removeValue(forKey: identifier) }
    saveSpotlightPayloads(stored)
    CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: identifiers) { error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(
            code: "SPOTLIGHT_REMOVE_FAILED",
            message: error.localizedDescription,
            details: nil
          ))
        } else {
          result(nil)
        }
      }
    }
  }

  private static func removeAllIndexes(result: @escaping FlutterResult) {
    saveSpotlightPayloads([:])
    CSSearchableIndex.default().deleteSearchableItems(
      withDomainIdentifiers: [spotlightDomain]
    ) { error in
      DispatchQueue.main.async {
        if let error {
          result(FlutterError(
            code: "SPOTLIGHT_REMOVE_FAILED",
            message: error.localizedDescription,
            details: nil
          ))
        } else {
          result(nil)
        }
      }
    }
  }

  private static func spotlightPayloads() -> [String: [String: Any]] {
    UserDefaults.standard.dictionary(forKey: spotlightDefaultsKey) as? [String: [String: Any]] ?? [:]
  }

  private static func saveSpotlightPayloads(_ payloads: [String: [String: Any]]) {
    UserDefaults.standard.set(payloads, forKey: spotlightDefaultsKey)
  }

  private static func donateActions(
    _ arguments: [String: Any]?,
    result: @escaping FlutterResult
  ) {
    guard let actions = arguments?["actions"] as? [[String: Any]] else {
      result(FlutterError(code: "BAD_ACTIONS", message: "快捷动作格式不正确", details: nil))
      return
    }
    for action in actions {
      guard let name = action["action"] as? String,
            ["continueReading", "searchBooks", "startListening", "pauseListening"].contains(name),
            let title = action["title"] as? String else {
        result(FlutterError(code: "BAD_ACTION", message: "不支持的快捷动作", details: nil))
        return
      }
      donatedActivity(
        action: name,
        title: title,
        phrase: action["phrase"] as? String,
        query: action["query"] as? String
      ).becomeCurrent()
    }
    result(nil)
  }

  private static func donatedActivity(
    action: String,
    title: String,
    phrase: String?,
    query: String?
  ) -> NSUserActivity {
    let activityType: String
    switch action {
    case "continueReading": activityType = continueReadingActivity
    case "searchBooks": activityType = searchBooksActivity
    case "startListening": activityType = startListeningActivity
    case "pauseListening": activityType = pauseListeningActivity
    default: activityType = openBookActivity
    }
    var userInfo: [String: Any] = [
      "action": action,
      "eventId": UUID().uuidString,
    ]
    if let query, !query.isEmpty { userInfo["query"] = query }
    let activity = NSUserActivity(activityType: activityType)
    activity.title = title
    activity.userInfo = userInfo
    activity.requiredUserInfoKeys = ["action", "eventId"]
    activity.persistentIdentifier = "shortcut.\(action)"
    activity.suggestedInvocationPhrase = phrase
    activity.isEligibleForHandoff = false
    activity.isEligibleForSearch = true
    activity.isEligibleForPrediction = true
    activity.isEligibleForPublicIndexing = false
    return activity
  }

  private static func shortcutTitle(for action: String) -> String {
    switch action {
    case "continueReading": return "继续阅读"
    case "searchBooks": return "搜索书籍"
    case "startListening": return "开始听书"
    case "pauseListening": return "暂停听书"
    default: return "轻小说文库"
    }
  }
}

@available(iOS 16.0, *)
struct WenkuContinueReadingIntent: AppIntent {
  static var title: LocalizedStringResource = "继续阅读"
  static var openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    AppleCapabilitiesPlugin.performShortcut(action: "continueReading")
    return .result()
  }
}

@available(iOS 16.0, *)
struct WenkuSearchBooksIntent: AppIntent {
  static var title: LocalizedStringResource = "搜索书籍"
  static var openAppWhenRun = true

  @Parameter(title: "书名或关键词")
  var query: String?

  init() {}

  func perform() async throws -> some IntentResult {
    AppleCapabilitiesPlugin.performShortcut(action: "searchBooks", query: query)
    return .result()
  }
}

@available(iOS 16.0, *)
struct WenkuStartListeningIntent: AppIntent {
  static var title: LocalizedStringResource = "开始听书"
  static var openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    AppleCapabilitiesPlugin.performShortcut(action: "startListening")
    return .result()
  }
}

@available(iOS 16.0, *)
struct WenkuPauseListeningIntent: AppIntent {
  static var title: LocalizedStringResource = "暂停听书"
  static var openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    AppleCapabilitiesPlugin.performShortcut(action: "pauseListening")
    return .result()
  }
}

@available(iOS 16.0, *)
struct WenkuAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: WenkuContinueReadingIntent(),
      phrases: ["用\(.applicationName)继续阅读"],
      shortTitle: "继续阅读",
      systemImageName: "book"
    )
    AppShortcut(
      intent: WenkuSearchBooksIntent(),
      phrases: ["用\(.applicationName)搜索书籍"],
      shortTitle: "搜索书籍",
      systemImageName: "magnifyingglass"
    )
    AppShortcut(
      intent: WenkuStartListeningIntent(),
      phrases: ["用\(.applicationName)开始听书"],
      shortTitle: "开始听书",
      systemImageName: "headphones"
    )
    AppShortcut(
      intent: WenkuPauseListeningIntent(),
      phrases: ["用\(.applicationName)暂停听书"],
      shortTitle: "暂停听书",
      systemImageName: "pause.fill"
    )
  }
}
