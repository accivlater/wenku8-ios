import Flutter
import Security

final class CloudSourcePlugin: NSObject, FlutterPlugin {
  private let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.zhujinyu.wenku8flutter.cloud-sources",
    kSecAttrAccount as String: "connections",
  ]

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "org.mewx.wenku8/cloud_sources",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(CloudSourcePlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "read":
      var request = query
      request[kSecReturnData as String] = true
      request[kSecMatchLimit as String] = kSecMatchLimitOne
      var item: CFTypeRef?
      let status = SecItemCopyMatching(request as CFDictionary, &item)
      if status == errSecItemNotFound {
        result(nil)
      } else if status == errSecSuccess,
        let data = item as? Data,
        let text = String(data: data, encoding: .utf8)
      {
        result(text)
      } else {
        result(FlutterError(code: "VAULT_READ", message: "无法读取网盘连接，请重新保存", details: nil))
      }
    case "write":
      if call.arguments == nil || call.arguments is NSNull {
        finish(SecItemDelete(query as CFDictionary), result: result)
        return
      }
      guard let text = call.arguments as? String,
        let data = text.data(using: .utf8),
        data.count <= 64 * 1024
      else {
        result(FlutterError(code: "VAULT_INPUT", message: "网盘连接格式不正确", details: nil))
        return
      }
      let status: OSStatus
      if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
        status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
      } else {
        var attributes = query
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecValueData as String] = data
        status = SecItemAdd(attributes as CFDictionary, nil)
      }
      finish(status, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func finish(_ status: OSStatus, result: @escaping FlutterResult) {
    if status == errSecSuccess || status == errSecItemNotFound {
      result(nil)
    } else {
      result(FlutterError(code: "VAULT_WRITE", message: "无法保存网盘连接，请重试", details: nil))
    }
  }
}
