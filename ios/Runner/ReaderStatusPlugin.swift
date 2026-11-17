import Flutter
import UIKit

final class ReaderStatusPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var observers: [NSObjectProtocol] = []
  private var timer: Timer?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterEventChannel(
      name: "org.mewx.wenku8/reader_status",
      binaryMessenger: registrar.messenger()
    )
    channel.setStreamHandler(ReaderStatusPlugin())
  }

  static func currentStatus() -> [String: Any] {
    let device = UIDevice.current
    let wasMonitoring = device.isBatteryMonitoringEnabled
    device.isBatteryMonitoringEnabled = true
    defer { device.isBatteryMonitoringEnabled = wasMonitoring }
    let level = device.batteryLevel
    let state = device.batteryState
    var status: [String: Any] = [
      "time": Int(Date().timeIntervalSince1970 * 1000),
      "charging": state == .charging || state == .full,
    ]
    if level >= 0 && level <= 1 { status["battery"] = Int((level * 100).rounded()) }
    return status
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    onCancel(withArguments: arguments)
    sink = events
    UIDevice.current.isBatteryMonitoringEnabled = true
    for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification] {
      observers.append(NotificationCenter.default.addObserver(
        forName: name,
        object: nil,
        queue: .main
      ) { [weak self] _ in self?.publish() })
    }
    timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      self?.publish()
    }
    publish()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    observers.forEach(NotificationCenter.default.removeObserver)
    observers.removeAll()
    timer?.invalidate()
    timer = nil
    sink = nil
    UIDevice.current.isBatteryMonitoringEnabled = false
    return nil
  }

  private func publish() {
    sink?(Self.currentStatus())
  }
}
