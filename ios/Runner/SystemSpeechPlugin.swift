import AVFoundation
import Flutter
import UIKit

private final class SpeechRequest {
  let id: String
  let output: URL
  let synthesizer = AVSpeechSynthesizer()
  let result: FlutterResult
  private let lock = NSLock()
  private var audioFile: AVAudioFile?
  private var failure: Error?
  private var frames: Int64 = 0
  private var completed = false
  var timeout: Timer?

  init(id: String, output: URL, result: @escaping FlutterResult) {
    self.id = id
    self.output = output
    self.result = result
  }

  func append(_ buffer: AVAudioPCMBuffer) -> Error? {
    lock.lock()
    defer { lock.unlock() }
    guard !completed, failure == nil else { return failure }
    do {
      if audioFile == nil {
        audioFile = try AVAudioFile(
          forWriting: output,
          settings: buffer.format.settings,
          commonFormat: buffer.format.commonFormat,
          interleaved: buffer.format.isInterleaved
        )
      }
      try audioFile?.write(from: buffer)
      frames += Int64(buffer.frameLength)
    } catch {
      failure = error
      return error
    }
    return nil
  }

  func complete() -> (result: FlutterResult, failure: Error?, frames: Int64)? {
    lock.lock()
    defer { lock.unlock() }
    guard !completed else { return nil }
    completed = true
    audioFile = nil
    return (result, failure, frames)
  }
}

final class SystemSpeechPlugin: NSObject, FlutterPlugin, AVSpeechSynthesizerDelegate {
  private var requests: [String: SpeechRequest] = [:]
  private var activeEngine: String?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "org.mewx.wenku8/system_speech",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(SystemSpeechPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "engines":
      result([["id": "@default", "name": "Apple"]])
    case "voices":
      guard validEngine(arguments?["engine"] as? String) else {
        result(FlutterError(code: "TTS_ENGINE", message: "该系统语音引擎不可用", details: nil))
        return
      }
      result(AVSpeechSynthesisVoice.speechVoices().map { voice in
        [
          "id": voice.identifier,
          "locale": voice.language,
          "networkRequired": false,
          "quality": voice.quality.rawValue,
        ]
      })
    case "settings":
      result(FlutterError(
        code: "TTS_SETTINGS",
        message: "请在系统设置的「辅助功能 > 朗读内容 > 声音」中管理语音",
        details: nil
      ))
    case "synthesize":
      synthesize(arguments, result: result)
    case "cancel":
      if let id = arguments?["requestId"] as? String,
        let request = requests[id]
      {
        finish(request, error: FlutterError(code: "TTS_CANCELLED", message: "合成已取消", details: nil))
        request.synthesizer.stopSpeaking(at: .immediate)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func validEngine(_ engine: String?) -> Bool {
    engine == nil || engine == "@default"
  }

  private func synthesize(_ arguments: [String: Any]?, result: @escaping FlutterResult) {
    guard let arguments,
      let text = arguments["text"] as? String,
      let path = arguments["path"] as? String,
      let requestId = arguments["requestId"] as? String,
      requestId.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      text.count <= 3500,
      validEngine(arguments["engine"] as? String)
    else {
      result(FlutterError(code: "TTS_INPUT", message: "语音文本、引擎或请求参数无效", details: nil))
      return
    }
    let output = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .resolvingSymlinksInPath().path + "/"
    guard output.path.hasPrefix(cacheRoot),
      output.lastPathComponent.range(
        of: "^[a-f0-9]{64}\\.wav\\.part$",
        options: .regularExpression
      ) != nil
    else {
      result(FlutterError(code: "TTS_INPUT", message: "语音缓存位置无效", details: nil))
      return
    }
    let engine = arguments["engine"] as? String ?? "@default"
    if let activeEngine, activeEngine != engine {
      let previous = Array(requests.values)
      for request in previous {
        finish(request, error: FlutterError(code: "TTS_CANCELLED", message: "语音引擎已切换", details: nil))
        request.synthesizer.stopSpeaking(at: .immediate)
      }
    }
    guard requests.isEmpty else {
      result(FlutterError(code: "TTS_BUSY", message: "系统语音正在准备上一段", details: nil))
      return
    }
    activeEngine = engine

    let utterance = AVSpeechUtterance(string: text)
    let voiceId = arguments["voice"] as? String
    if let voiceId, !voiceId.isEmpty, voiceId != "@default" {
      guard let voice = AVSpeechSynthesisVoice(identifier: voiceId) else {
        result(FlutterError(code: "TTS_VOICE", message: "该系统音色暂未就绪", details: nil))
        return
      }
      utterance.voice = voice
    }
    let locale = arguments["locale"] as? String
    if utterance.voice == nil, let locale, !locale.isEmpty {
      guard let voice = AVSpeechSynthesisVoice(language: locale) else {
        result(FlutterError(code: "TTS_LANGUAGE_UNAVAILABLE", message: "没有对应语言的语音模型", details: nil))
        return
      }
      utterance.voice = voice
    }
    if let locale, !locale.isEmpty, let voice = utterance.voice,
      Self.language(locale) != Self.language(voice.language)
    {
      result(FlutterError(code: "TTS_LANGUAGE_UNAVAILABLE", message: "该音色不支持对应语言", details: nil))
      return
    }
    let speed = (arguments["rate"] ?? arguments["speed"] ?? arguments["speechRate"]) as? NSNumber
    if let speed, !speed.doubleValue.isFinite || speed.doubleValue < 0.5 || speed.doubleValue > 2.0 {
      result(FlutterError(code: "TTS_INPUT", message: "语速超出 0.5 至 2.0 倍范围", details: nil))
      return
    }
    let multiplier = speed.map { Float(truncating: $0) } ?? 1.0
    utterance.rate = min(
      AVSpeechUtteranceMaximumSpeechRate,
      max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * multiplier)
    )
    utterance.pitchMultiplier = 1.0

    do {
      try FileManager.default.createDirectory(
        at: output.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      if FileManager.default.fileExists(atPath: output.path) {
        try FileManager.default.removeItem(at: output)
      }
    } catch {
      result(FlutterError(code: "TTS_WRITE", message: "语音缓存文件无法写入", details: nil))
      return
    }

    let request = SpeechRequest(id: requestId, output: output, result: result)
    requests[requestId] = request
    request.synthesizer.delegate = self
    request.timeout = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self, weak request] _ in
      guard let self, let request else { return }
      self.finish(request, error: FlutterError(code: "TTS_TIMEOUT", message: "系统语音合成超时", details: nil))
      request.synthesizer.stopSpeaking(at: .immediate)
    }
    request.synthesizer.write(utterance) { [weak self, weak request] buffer in
      guard let self, let request, let pcm = buffer as? AVAudioPCMBuffer else { return }
      if let failure = request.append(pcm) {
        self.finish(request, error: FlutterError(
          code: "TTS_WRITE",
          message: "语音音频写入失败：\(failure.localizedDescription)",
          details: nil
        ))
        request.synthesizer.stopSpeaking(at: .immediate)
      }
    }
  }

  private static func language(_ value: String) -> String {
    value.replacingOccurrences(of: "_", with: "-")
      .split(separator: "-")
      .first?
      .lowercased() ?? value.lowercased()
  }

  private func finish(_ request: SpeechRequest, error: FlutterError?) {
    let completion = { [weak self] in
      guard let self else { return }
      if let current = requests[request.id], current === request {
        requests.removeValue(forKey: request.id)
      }
      request.timeout?.invalidate()
      request.timeout = nil
      guard let completed = request.complete() else { return }
      let failure = completed.failure
      if error == nil, failure == nil, completed.frames > 0,
        let attributes = try? FileManager.default.attributesOfItem(atPath: request.output.path),
        let size = attributes[.size] as? NSNumber,
        size.int64Value > 44
      {
        completed.result(request.output.path)
      } else {
        try? FileManager.default.removeItem(at: request.output)
        if let failure {
          completed.result(FlutterError(
            code: "TTS_WRITE",
            message: "语音音频写入失败：\(failure.localizedDescription)",
            details: nil
          ))
        } else if let error {
          completed.result(error)
        } else {
          completed.result(FlutterError(
            code: "TTS_CONTENT",
            message: "系统语音没有生成有效音频",
            details: nil
          ))
        }
      }
    }
    if Thread.isMainThread {
      completion()
    } else {
      DispatchQueue.main.async(execute: completion)
    }
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    guard let request = requests.first(where: { $0.value.synthesizer === synthesizer })?.value else { return }
    finish(request, error: nil)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    guard let request = requests.first(where: { $0.value.synthesizer === synthesizer })?.value else { return }
    finish(request, error: FlutterError(code: "TTS_CANCELLED", message: "合成已取消", details: nil))
  }

  deinit {
    for request in requests.values {
      request.timeout?.invalidate()
      request.synthesizer.stopSpeaking(at: .immediate)
      try? FileManager.default.removeItem(at: request.output)
    }
  }
}
