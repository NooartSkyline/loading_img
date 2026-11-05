import AVFoundation
import Flutter
import UIKit

final class DownloadKeepAlive: NSObject {
  static let shared = DownloadKeepAlive()

  private var holds = 0
  private var player: AVAudioPlayer?
  private var task = UIBackgroundTaskIdentifier.invalid

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "loading/keep_alive", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "acquire":
        self.acquire()
        result(nil)
      case "release":
        self.release()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func acquire() {
    holds += 1
    guard holds == 1 else { return }
    UIApplication.shared.isIdleTimerDisabled = true
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
    try? session.setActive(true)
    player = try? AVAudioPlayer(data: silentWav())
    player?.numberOfLoops = -1
    player?.volume = 1
    player?.play()
    task = UIApplication.shared.beginBackgroundTask { [weak self] in
      self?.finishTask()
    }
  }

  private func release() {
    guard holds > 0 else { return }
    holds -= 1
    guard holds == 0 else { return }
    player?.stop()
    player = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    UIApplication.shared.isIdleTimerDisabled = false
    finishTask()
  }

  private func finishTask() {
    guard task != .invalid else { return }
    UIApplication.shared.endBackgroundTask(task)
    task = .invalid
  }

  private func silentWav() -> Data {
    let sampleRate = 8_000
    let samples = sampleRate
    let dataSize = samples * 2
    var bytes = Data()
    func text(_ value: String) { bytes.append(contentsOf: value.utf8) }
    func u32(_ value: UInt32) {
      var little = value.littleEndian
      bytes.append(Data(bytes: &little, count: 4))
    }
    func u16(_ value: UInt16) {
      var little = value.littleEndian
      bytes.append(Data(bytes: &little, count: 2))
    }
    text("RIFF")
    u32(UInt32(36 + dataSize))
    text("WAVE")
    text("fmt ")
    u32(16)
    u16(1)
    u16(1)
    u32(UInt32(sampleRate))
    u32(UInt32(sampleRate * 2))
    u16(2)
    u16(16)
    text("data")
    u32(UInt32(dataSize))
    for _ in 0..<samples {
      u16(1)
    }
    return bytes
  }
}
