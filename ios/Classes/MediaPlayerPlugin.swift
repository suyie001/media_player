import Flutter
import UIKit
import AVFoundation  // 添加这行

public class MediaPlayerPlugin: NSObject, FlutterPlugin {
    private let mediaPlayer = MediaPlayerHandler()
    private var videoViewFactory: MediaPlayerVideoViewFactory?
    private var eventSink: FlutterEventSink?
    private var registrar: FlutterPluginRegistrar?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "media_player", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "media_player_events", binaryMessenger: registrar.messenger())
        
        let instance = MediaPlayerPlugin()
        instance.registrar = registrar
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "showVideoView":
            // 创建并注册视频视图工厂
            if videoViewFactory == nil {
                videoViewFactory = MediaPlayerVideoViewFactory(player: mediaPlayer.player)
                registrar?.register(videoViewFactory!, withId: "media_player_video_view")
            }
            result(nil)
            
        case "hideVideoView":
            // 移除视频视图工厂
            videoViewFactory = nil
            result(nil)
            
        case "initialize":
            result(nil)
            
        case "setPlaylist":
            guard let args = call.arguments as? [String: Any],
                  let playlist = args["playlist"] as? [[String: Any]] else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "Playlist is required",
                                  details: nil))
                return
            }
            mediaPlayer.setPlaylist(playlist)
            result(nil)
            
        case "setPlayMode":
            guard let args = call.arguments as? [String: Any],
                  let mode = args["mode"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "Play mode is required",
                                  details: nil))
                return
            }
            mediaPlayer.setPlayMode(mode)
            result(nil)
            
        case "getPlayMode":
            result(mediaPlayer.getPlayMode())
            
        case "add":
            guard let args = call.arguments as? [String: Any],
                  let mediaItem = args["mediaItem"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "MediaItem is required",
                                  details: nil))
                return
            }
            mediaPlayer.add(mediaItem)
            result(nil)
            
        case "removeAt":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "Index is required",
                                  details: nil))
                return
            }
            mediaPlayer.removeAt(index)
            result(nil)
            
        case "insertAt":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int,
                  let mediaItem = args["mediaItem"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "Index and mediaItem are required",
                                  details: nil))
                return
            }
            mediaPlayer.insertAt(index, mediaItem: mediaItem)
            result(nil)
            
        case "move":
            guard let args = call.arguments as? [String: Any],
                  let from = args["from"] as? Int,
                  let to = args["to"] as? Int else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "From and to indices are required",
                                  details: nil))
                return
            }
            mediaPlayer.move(from, to)
            result(nil)
            
        case "jumpTo":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "Index is required",
                                  details: nil))
                return
            }
            mediaPlayer.jumpTo(index)
            result(nil)
            
        case "play":
            mediaPlayer.play()
            result(nil)
            
        case "pause":
            mediaPlayer.pause()
            result(nil)
            
        case "stop":
            mediaPlayer.stop()
            result(nil)
            
        case "seekTo":
            guard let args = call.arguments as? [String: Any],
                  let position = args["position"] as? Int else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "Position is required",
                                  details: nil))
                return
            }
            mediaPlayer.seekTo(position: TimeInterval(position) / 1000.0)
            result(nil)
            
        case "skipToNext":
            mediaPlayer.skipToNext()
            result(nil)
            
        case "skipToPrevious":
            mediaPlayer.skipToPrevious()
            result(nil)
            
        case "setVolume":
            guard let args = call.arguments as? [String: Any],
                  let volume = args["volume"] as? Double else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "Volume is required",
                                  details: nil))
                return
            }
            mediaPlayer.setVolume(Float(volume))
            result(nil)
            
    
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

// MARK: - FlutterStreamHandler

extension MediaPlayerPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        mediaPlayer.setEventSink(events)
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        mediaPlayer.setEventSink { _ in }
        return nil
    }
}

class MediaPlayerVideoViewFactory: NSObject, FlutterPlatformViewFactory {
    private let player: AVPlayer
    private var eventSink: FlutterEventSink?
    
    init(player: AVPlayer) {
        self.player = player
        super.init()
    }
    
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        return VideoPlayerView(frame: frame, player: player, eventSink: eventSink)
    }
    
    func setEventSink(_ sink: FlutterEventSink?) {
        self.eventSink = sink
    }
}

class VideoPlayerView: NSObject, FlutterPlatformView {
    private let playerLayer: AVPlayerLayer
    private let containerView: UIView
    private var eventSink: FlutterEventSink?
    
    init(frame: CGRect, player: AVPlayer, eventSink: FlutterEventSink?) {
        containerView = UIView(frame: frame)
        playerLayer = AVPlayerLayer(player: player)
        self.eventSink = eventSink
        super.init()
        
        setupView()
    }
    
    private func setupView() {
        containerView.backgroundColor = .clear
        containerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        playerLayer.frame = containerView.bounds
        playerLayer.videoGravity = .resizeAspect
        containerView.layer.addSublayer(playerLayer)
    }
    
    func view() -> UIView {
        return containerView
    }
}