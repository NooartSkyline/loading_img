import AVFoundation
import Flutter

enum TrackMux {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "loading/mux", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "combine" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any]
      guard
        let video = args?["video"] as? String,
        let audio = args?["audio"] as? String,
        let output = args?["output"] as? String
      else {
        result(FlutterError(code: "mux", message: "ไฟล์ไม่ครบ", details: nil))
        return
      }
      combine(
        video: URL(fileURLWithPath: video),
        audio: URL(fileURLWithPath: audio),
        output: URL(fileURLWithPath: output),
        result: result
      )
    }
  }

  private static func combine(video: URL, audio: URL, output: URL, result: @escaping FlutterResult) {
    Task {
      let videoAsset = AVURLAsset(url: video)
      let audioAsset = AVURLAsset(url: audio)
      do {
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        guard
          let videoTrack = videoTracks.first,
          let audioTrack = audioTracks.first
        else {
          finish(result, FlutterError(code: "mux", message: "รวมภาพกับเสียงไม่ได้", details: nil))
          return
        }
        let composition = AVMutableComposition()
        guard
          let outVideo = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
          ),
          let outAudio = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
          )
        else {
          finish(result, FlutterError(code: "mux", message: "รวมภาพกับเสียงไม่ได้", details: nil))
          return
        }
        try outVideo.insertTimeRange(
          CMTimeRange(start: .zero, duration: videoDuration),
          of: videoTrack,
          at: .zero
        )
        try outAudio.insertTimeRange(
          CMTimeRange(start: .zero, duration: audioDuration),
          of: audioTrack,
          at: .zero
        )
        if FileManager.default.fileExists(atPath: output.path) {
          try? FileManager.default.removeItem(at: output)
        }
        guard
          let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
          )
        else {
          finish(result, FlutterError(code: "mux", message: "รวมภาพกับเสียงไม่ได้", details: nil))
          return
        }
        session.outputURL = output
        session.outputFileType = .mp4
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
          session.exportAsynchronously {
            continuation.resume()
          }
        }
        if session.status == .completed {
          finish(result, nil)
        } else {
          finish(result, FlutterError(code: "mux", message: "รวมภาพกับเสียงไม่ได้", details: nil))
        }
      } catch {
        finish(result, FlutterError(code: "mux", message: "รวมภาพกับเสียงไม่ได้", details: nil))
      }
    }
  }

  private static func finish(_ result: @escaping FlutterResult, _ value: Any?) {
    DispatchQueue.main.async {
      result(value)
    }
  }
}
