import Flutter
import Network
import UIKit

final class NetworkStatusPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let monitorQueue = DispatchQueue(label: "org.mewx.wenku8.network-status")
  private var monitor: NWPathMonitor?
  private var monitorGeneration = 0
  private var eventSink: FlutterEventSink?
  private var currentState = "unknown"
  private var publishedState: String?
  private var pendingPublish: DispatchWorkItem?
  private var observers: [NSObjectProtocol] = []

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = NetworkStatusPlugin()
    let methods = FlutterMethodChannel(
      name: "org.mewx.wenku8/network_status",
      binaryMessenger: registrar.messenger()
    )
    let events = FlutterEventChannel(
      name: "org.mewx.wenku8/network_events",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methods)
    events.setStreamHandler(instance)
    instance.observeLifecycle()
    instance.startMonitor()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "current" else {
      result(FlutterMethodNotImplemented)
      return
    }
    if let monitor {
      accept(monitor.currentPath)
    }
    result(currentState)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    publishedState = nil
    startMonitor()
    publishCurrent(immediate: true)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    pendingPublish?.cancel()
    pendingPublish = nil
    eventSink = nil
    publishedState = nil
    return nil
  }

  private func observeLifecycle() {
    let center = NotificationCenter.default
    observers.append(center.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.stopMonitor()
    })
    observers.append(center.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      self.currentState = "checking"
      self.startMonitor()
      self.publishCurrent(immediate: true)
    })
  }

  private func startMonitor() {
    stopMonitor()
    monitorGeneration += 1
    let generation = monitorGeneration
    let monitor = NWPathMonitor()
    self.monitor = monitor
    monitor.pathUpdateHandler = { [weak self] path in
      DispatchQueue.main.async {
        guard let self, self.monitorGeneration == generation else { return }
        self.accept(path)
      }
    }
    monitor.start(queue: monitorQueue)
  }

  private func stopMonitor() {
    monitorGeneration += 1
    monitor?.cancel()
    monitor = nil
    pendingPublish?.cancel()
    pendingPublish = nil
  }

  private func accept(_ path: NWPath) {
    let state: String
    switch path.status {
    case .satisfied:
      state = "online"
    case .unsatisfied:
      state = "offline"
    case .requiresConnection:
      state = "checking"
    @unknown default:
      state = "unknown"
    }
    currentState = state
    publishCurrent()
  }

  private func publishCurrent(immediate: Bool = false) {
    pendingPublish?.cancel()
    pendingPublish = nil
    guard eventSink != nil, currentState != publishedState else { return }
    let state = currentState
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.currentState == state, self.publishedState != state else { return }
      self.pendingPublish = nil
      self.publishedState = state
      self.eventSink?(state)
    }
    pendingPublish = work
    if immediate {
      DispatchQueue.main.async(execute: work)
    } else {
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250), execute: work)
    }
  }

  deinit {
    stopMonitor()
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
  }
}
