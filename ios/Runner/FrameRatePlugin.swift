import Flutter
import UIKit

final class FrameRatePlugin: NSObject, FlutterPlugin {
  private var target = 0.0

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "org.mewx.wenku8/frame_rate",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(FrameRatePlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "info":
      result([
        "target": target,
        "current": Double(UIScreen.main.maximumFramesPerSecond),
        "rates": [],
      ])
    case "set":
      guard let arguments = call.arguments as? [String: Any],
        let requested = (arguments["target"] as? NSNumber)?.doubleValue,
        requested == 0 || requested == -1
      else {
        result(FlutterError(
          code: "unsupported",
          message: "iOS 不支持按应用锁定刷新率，请选择自动高刷或系统调度",
          details: nil
        ))
        return
      }
      target = requested
      handle(FlutterMethodCall(methodName: "info", arguments: nil), result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
