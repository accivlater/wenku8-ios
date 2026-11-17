import Flutter
import Network
import Security
import UIKit

private enum LanDiscoveryInputError: Error {
  case invalid
}

private struct LanResolution {
  let key: String
  let service: NetService
}

private final class LanReadingConfigPlugin: NSObject, FlutterPlugin {
  private static let channelName = "org.mewx.wenku8/lan_reading_config"
  private let legacyKey = "lanReading.configuration.v1"
  private let service = "com.zhujinyu.wenku8flutter.lan-reading-configuration"
  private let account = "pairings"
  private var legacyCleanupRequired = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(LanReadingConfigPlugin(), channel: channel)
  }

  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "read":
      read(result)
    case "write":
      write(call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func validatedData(_ text: String) -> Data? {
    guard let data = text.data(using: .utf8),
      data.count <= 1024 * 1024,
      (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
    else {
      return nil
    }
    return data
  }

  private func readData() -> (OSStatus, Data?) {
    var request = query
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &item)
    return (status, item as? Data)
  }

  private func writeData(_ data: Data) -> OSStatus {
    let existing = SecItemCopyMatching(query as CFDictionary, nil)
    if existing == errSecSuccess {
      return SecItemUpdate(query as CFDictionary, [
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      ] as CFDictionary)
    }
    guard existing == errSecItemNotFound else { return existing }
    var item = query
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    item[kSecAttrSynchronizable as String] = false
    item[kSecValueData as String] = data
    return SecItemAdd(item as CFDictionary, nil)
  }

  private func removeLegacy() -> Bool {
    let defaults = UserDefaults.standard
    guard legacyCleanupRequired || defaults.object(forKey: legacyKey) != nil else { return true }
    legacyCleanupRequired = true
    defaults.removeObject(forKey: legacyKey)
    let synchronized = defaults.synchronize()
    legacyCleanupRequired = !synchronized || defaults.object(forKey: legacyKey) != nil
    return !legacyCleanupRequired
  }

  private func read(_ result: @escaping FlutterResult) {
    let (status, data) = readData()
    if status == errSecSuccess {
      guard let data,
        let text = String(data: data, encoding: .utf8),
        validatedData(text) != nil
      else {
        result(FlutterError(code: "LAN_CONFIG_READ", message: "局域网配置已损坏，未清除或重置配对", details: nil))
        return
      }
      guard removeLegacy() else {
        result(FlutterError(code: "LAN_CONFIG_MIGRATION", message: "旧配置明文尚未删除，请重试完成迁移", details: nil))
        return
      }
      result(text)
      return
    }
    guard status == errSecItemNotFound else {
      result(FlutterError(code: "LAN_CONFIG_KEYCHAIN", message: "无法安全读取局域网配置（\(status)），未重置配对", details: nil))
      return
    }
    let defaults = UserDefaults.standard
    guard let legacy = defaults.string(forKey: legacyKey) else {
      if defaults.object(forKey: legacyKey) == nil {
        result(nil)
      } else {
        result(FlutterError(code: "LAN_CONFIG_READ", message: "旧局域网配置无法读取，未重置配对", details: nil))
      }
      return
    }
    guard let legacyData = validatedData(legacy) else {
      result(FlutterError(code: "LAN_CONFIG_READ", message: "旧局域网配置已损坏，未重置配对", details: nil))
      return
    }
    let writeStatus = writeData(legacyData)
    guard writeStatus == errSecSuccess else {
      result(FlutterError(code: "LAN_CONFIG_KEYCHAIN", message: "无法将旧配置迁移到 Keychain（\(writeStatus)），原配置已保留", details: nil))
      return
    }
    guard removeLegacy() else {
      result(FlutterError(code: "LAN_CONFIG_MIGRATION", message: "配置已写入 Keychain，但旧明文尚未删除，请重试", details: nil))
      return
    }
    result(legacy)
  }

  private func write(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let text = arguments as? String, let data = validatedData(text) else {
      result(FlutterError(code: "LAN_CONFIG", message: "局域网配置格式无效", details: nil))
      return
    }
    let status = writeData(data)
    guard status == errSecSuccess else {
      result(FlutterError(code: "LAN_CONFIG_KEYCHAIN", message: "无法安全保存局域网配置（\(status)）", details: nil))
      return
    }
    guard removeLegacy() else {
      result(FlutterError(code: "LAN_CONFIG_MIGRATION", message: "新配置已保存，但旧明文尚未删除，请重试", details: nil))
      return
    }
    result(nil)
  }
}

final class LanDiscoveryPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let defaultService = "_wenkuread._tcp"
  private let browserQueue = DispatchQueue(label: "org.mewx.wenku8.lan-discovery")
  private var channel: FlutterMethodChannel?
  private var eventSink: FlutterEventSink?
  private var browser: NWBrowser?
  private var advertiser: NetService?
  private var resolving: [ObjectIdentifier: LanResolution] = [:]
  private var present: Set<String> = []
  private var found: [String: [String: Any]] = [:]
  private var ownId = ""
  private var ownName = ""
  private var discoveryGeneration = 0

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = LanDiscoveryPlugin()
    let channel = FlutterMethodChannel(
      name: "org.mewx.wenku8/lan_discovery",
      binaryMessenger: registrar.messenger()
    )
    let events = FlutterEventChannel(
      name: "org.mewx.wenku8/lan_discovery_events",
      binaryMessenger: registrar.messenger()
    )
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    events.setStreamHandler(instance)
    LanReadingConfigPlugin.register(with: registrar)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    do {
      switch call.method {
      case "startDiscovery":
        ownId = arguments?["id"] as? String ?? arguments?["name"] as? String ?? ownId
        ownName = arguments?["name"] as? String ?? ownName
        try startDiscovery(service: arguments?["service"] as? String)
        result(nil)
      case "stopDiscovery":
        stopDiscovery()
        result(nil)
      case "startAdvertising":
        let name = try deviceName(arguments?["name"] as? String)
        let port = try validPort(arguments?["port"])
        let advertisedId = arguments?["id"] as? String
        ownName = name
        ownId = advertisedId ?? name
        try startAdvertising(
          name: name,
          serviceName: name,
          port: port,
          service: arguments?["service"] as? String,
          id: advertisedId
        )
        result(UIDevice.current.name)
      case "stopAdvertising":
        stopAdvertising()
        result(nil)
      case "start":
        guard let id = arguments?["id"] as? String,
          id.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil
        else {
          throw LanDiscoveryInputError.invalid
        }
        let port = try validPort(arguments?["port"])
        stopAll()
        ownId = id
        let name = try deviceName(nil)
        ownName = name
        try startAdvertising(
          name: name,
          serviceName: "wenku-\(id.prefix(12))",
          port: port,
          service: nil,
          id: id
        )
        try startDiscovery(service: nil)
        result(name)
      case "stop":
        stopAll()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(
        code: "LAN_DISCOVERY",
        message: "自动发现暂不可用，请检查设备名称、端口和本地网络权限",
        details: nil
      ))
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func deviceName(_ proposed: String?) throws -> String {
    let value = (proposed ?? UIDevice.current.name).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { throw LanDiscoveryInputError.invalid }
    return String(value.prefix(64))
  }

  private func validPort(_ value: Any?) throws -> Int {
    guard let number = value as? NSNumber else { throw LanDiscoveryInputError.invalid }
    let port = number.intValue
    guard port >= 1024 && port <= 65535 else { throw LanDiscoveryInputError.invalid }
    return port
  }

  private func serviceType(_ proposed: String?) throws -> String {
    let requested = proposed ?? Self.defaultService
    let value = requested == "_wenku8-reading._tcp" || requested == "_wenku8-reading._tcp."
      ? Self.defaultService
      : requested
    guard value.count <= 64,
      value.range(
        of: "^_[A-Za-z0-9-]+\\._(tcp|udp)\\.?$",
        options: .regularExpression
      ) != nil
    else {
      throw LanDiscoveryInputError.invalid
    }
    return value.hasSuffix(".") ? String(value.dropLast()) : value
  }

  private func startDiscovery(service proposed: String?) throws {
    stopDiscovery()
    discoveryGeneration += 1
    let generation = discoveryGeneration
    let type = try serviceType(proposed)
    let browser = NWBrowser(
      for: .bonjour(type: type, domain: nil),
      using: NWParameters()
    )
    self.browser = browser
    browser.stateUpdateHandler = { [weak self] state in
      DispatchQueue.main.async {
        guard let self, self.discoveryGeneration == generation else { return }
        if case .failed(let error) = state {
          self.fail("局域网发现失败：\(error.localizedDescription)")
        }
      }
    }
    browser.browseResultsChangedHandler = { [weak self] _, changes in
      DispatchQueue.main.async {
        guard let self, self.discoveryGeneration == generation else { return }
        for change in changes {
          switch change {
          case .added(let result):
            self.add(result, generation: generation)
          case .removed(let result):
            self.remove(result, generation: generation)
          default:
            break
          }
        }
      }
    }
    browser.start(queue: browserQueue)
  }

  private func startAdvertising(
    name: String,
    serviceName: String,
    port: Int,
    service proposed: String?,
    id: String?
  ) throws {
    stopAdvertising()
    let type = try serviceType(proposed) + "."
    guard !serviceName.isEmpty, serviceName.utf8.count <= 63 else {
      throw LanDiscoveryInputError.invalid
    }
    let service = NetService(domain: "local.", type: type, name: serviceName, port: Int32(port))
    var txt: [String: Data] = [
      "name": Data(name.utf8),
      "v": Data("1".utf8),
    ]
    if let id, !id.isEmpty {
      txt["id"] = Data(id.utf8)
    }
    service.setTXTRecord(NetService.data(fromTXTRecord: txt))
    service.delegate = self
    service.schedule(in: .main, forMode: .common)
    advertiser = service
    service.publish()
  }

  private func serviceParts(_ result: NWBrowser.Result) -> (key: String, service: NetService)? {
    guard case .service(let name, let type, let domain, _) = result.endpoint else { return nil }
    let key = "\(name)|\(type)|\(domain)"
    let qualifiedType = type.hasSuffix(".") ? type : type + "."
    return (key, NetService(domain: domain, type: qualifiedType, name: name))
  }

  private func add(_ result: NWBrowser.Result, generation: Int) {
    guard let parts = serviceParts(result), !present.contains(parts.key) else { return }
    present.insert(parts.key)
    let service = parts.service
    let identity = ObjectIdentifier(service)
    resolving[identity] = LanResolution(key: parts.key, service: service)
    service.delegate = self
    service.schedule(in: .main, forMode: .common)
    service.resolve(withTimeout: 8)
  }

  private func remove(_ result: NWBrowser.Result, generation: Int) {
    guard generation == discoveryGeneration, let parts = serviceParts(result) else { return }
    present.remove(parts.key)
    if let entry = resolving.first(where: { $0.value.key == parts.key }) {
      entry.value.service.stop()
      resolving.removeValue(forKey: entry.key)
    }
    lost(parts.key)
  }

  private func accept(_ service: NetService) {
    let identity = ObjectIdentifier(service)
    guard let resolution = resolving.removeValue(forKey: identity) else { return }
    service.remove(from: .main, forMode: .common)
    let addresses = Self.privateAddresses(service)
    guard present.contains(resolution.key),
      service.port >= 1024 && service.port <= 65535,
      let host = addresses.first(where: { !$0.contains(":") }) ?? addresses.first,
      let txtData = service.txtRecordData(),
      let nameData = NetService.dictionary(fromTXTRecord: txtData)["name"],
      let name = String(data: nameData, encoding: .utf8),
      !name.isEmpty, name.count <= 64
    else {
      return
    }
    let txt = NetService.dictionary(fromTXTRecord: txtData)
    let id = txt["id"].flatMap { String(data: $0, encoding: .utf8) } ?? ""
    if !id.isEmpty {
      guard id.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil,
        txt["v"].flatMap({ String(data: $0, encoding: .utf8) }) == "1"
      else {
        return
      }
    }
    guard id != ownId, service.name != ownName else { return }
    let value: [String: Any] = [
      "id": id,
      "name": name,
      "host": host,
      "port": service.port,
    ]
    if let previous = found[resolution.key], NSDictionary(dictionary: previous).isEqual(value) {
      return
    }
    found[resolution.key] = value
    publishFound(value)
  }

  private func lost(_ key: String) {
    guard let value = found.removeValue(forKey: key) else { return }
    var event = value
    event["type"] = "lost"
    eventSink?(event)
    publishDevices()
  }

  private func publishFound(_ value: [String: Any]) {
    var event = value
    event["type"] = "found"
    eventSink?(event)
    publishDevices()
  }

  private func publishDevices() {
    channel?.invokeMethod("devices", arguments: found.values.filter { value in
      guard let id = value["id"] as? String else { return false }
      return !id.isEmpty
    })
  }

  private func fail(_ message: String) {
    stopAll()
    eventSink?([
      "type": "error",
      "name": "",
      "host": "",
      "port": 0,
      "message": message,
    ])
    channel?.invokeMethod("failure", arguments: nil)
  }

  private func stopDiscovery() {
    discoveryGeneration += 1
    browser?.cancel()
    browser = nil
    for entry in resolving.values {
      entry.service.delegate = nil
      entry.service.stop()
    }
    resolving.removeAll()
    present.removeAll()
    found.removeAll()
    publishDevices()
  }

  private func stopAdvertising() {
    advertiser?.delegate = nil
    advertiser?.stop()
    advertiser = nil
  }

  private func stopAll() {
    stopDiscovery()
    stopAdvertising()
  }

  private static func privateAddresses(_ service: NetService) -> [String] {
    (service.addresses ?? []).compactMap { data in
      data.withUnsafeBytes { raw -> String? in
        guard raw.count >= MemoryLayout<sockaddr>.size else { return nil }
        let socket = raw.bindMemory(to: sockaddr.self)[0]
        if Int32(socket.sa_family) == AF_INET,
          raw.count >= MemoryLayout<sockaddr_in>.size
        {
          var address = raw.bindMemory(to: sockaddr_in.self)[0].sin_addr
          var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
          inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count))
          let host = String(cString: buffer)
          let parts = host.split(separator: ".").compactMap { Int($0) }
          guard parts.count == 4, parts.allSatisfy({ $0 >= 0 && $0 <= 255 }) else { return nil }
          let privateAddress = parts[0] == 10 || parts[0] == 127 ||
            parts[0] == 192 && parts[1] == 168 ||
            parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31 ||
            parts[0] == 169 && parts[1] == 254
          return privateAddress ? host : nil
        }
        if Int32(socket.sa_family) == AF_INET6,
          raw.count >= MemoryLayout<sockaddr_in6>.size
        {
          var address = raw.bindMemory(to: sockaddr_in6.self)[0].sin6_addr
          var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
          inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count))
          let host = String(cString: buffer).lowercased()
          return host == "::1" || host.hasPrefix("fe80:") ? host : nil
        }
        return nil
      }
    }
  }
}

extension LanDiscoveryPlugin: NetServiceDelegate {
  func netServiceDidResolveAddress(_ sender: NetService) {
    accept(sender)
  }

  func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
    let identity = ObjectIdentifier(sender)
    resolving.removeValue(forKey: identity)
    sender.remove(from: .main, forMode: .common)
  }

  func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
    guard sender === advertiser else { return }
    fail("局域网广播未能发布")
  }
}
