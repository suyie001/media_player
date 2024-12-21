import Flutter
import UIKit
import AVFoundation  // 添加这行

public class MediaPlayerPlugin: NSObject, FlutterPlugin {
    private let mediaPlayer = MediaPlayerHandler()
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "media_player", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "media_player_events", binaryMessenger: registrar.messenger())
        
        let instance = MediaPlayerPlugin()
        let factory = VideoPlayerViewFactory(player: instance.mediaPlayer.player)
        
        // 注册视频视图工厂
        registrar.register(
            factory,
            withId: "video_player_view"
        )
        
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
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



class VideoPlayerViewFactory: NSObject, FlutterPlatformViewFactory {
    private let player: AVPlayer
    
    init(player: AVPlayer) {
        self.player = player
        super.init()
    }
    
    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return VideoPlayerView(
            frame: frame,
            viewIdentifier: viewId,
            player: player
        )
    }
    
    // 支持创建参数编码
    public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

class VideoPlayerView: NSObject, FlutterPlatformView {
    private let playerLayer: AVPlayerLayer
    private let containerView: UIView
    private var playerObservation: NSKeyValueObservation?
    
    init(frame: CGRect, viewIdentifier: Int64, player: AVPlayer) {
        containerView = UIView(frame: frame)
        playerLayer = AVPlayerLayer(player: player)
        super.init()
        
        setupView()
        setupObservers()
    }
    
    private func setupView() {
        // 配置容器视图
        containerView.backgroundColor = .black
        containerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // 配置播放器图层
        playerLayer.frame = containerView.bounds
        playerLayer.videoGravity = .resizeAspect
        containerView.layer.addSublayer(playerLayer)
        
        // 添加手势识别器支持全屏
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        containerView.addGestureRecognizer(tapGesture)
    }
    
    private func setupObservers() {
        // 监听播放器图层的绑定状态
        playerObservation = playerLayer.observe(\.isReadyForDisplay) { [weak self] layer, _ in
            if layer.isReadyForDisplay {
                self?.handlePlayerReady()
            }
        }
        
        // 监听设备方向变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
    
    private func handlePlayerReady() {
        // 可以在这里添加视频准备就绪后的处理逻辑
        updateVideoLayout()
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        // 处理点击事件，可以在这里实现全屏切换等功能
    }
    
    @objc private func orientationChanged() {
        updateVideoLayout()
    }
    
    private func updateVideoLayout() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        playerLayer.frame = containerView.bounds
        CATransaction.commit()
    }
    
    func view() -> UIView {
        return containerView
    }
    
    func updateFrame(_ frame: CGRect) {
        containerView.frame = frame
        updateVideoLayout()
    }
    
    deinit {
        playerObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

// import Flutter
// import UIKit
// import AVFoundation

// public class VideoPlayerFactory: NSObject, FlutterPlatformViewFactory {
//     private var messenger: FlutterBinaryMessenger

//     public init(messenger: FlutterBinaryMessenger) {
//         self.messenger = messenger
//         super.init()
//     }

//     public func create(
//         withFrame frame: CGRect,
//         viewIdentifier viewId: Int64,
//         arguments args: Any?
//     ) -> FlutterPlatformView {
//         return VideoPlayerView(
//             frame: frame,
//             viewIdentifier: viewId,
//             arguments: args,
//             binaryMessenger: messenger)
//     }
// }

// class VideoPlayerView: NSObject, FlutterPlatformView {
//     private let playerLayer: AVPlayerLayer
//     private let containerView: UIView
    
//     init(frame: CGRect, viewIdentifier: Int64, player: AVPlayer) {
//         containerView = UIView(frame: frame)
//         playerLayer = AVPlayerLayer(player: player)
//         super.init()
        
//         // 设置播放器图层
//         playerLayer.frame = containerView.bounds
//         playerLayer.videoGravity = .resizeAspect  // 可以根据需求调整视频缩放模式
//         containerView.layer.addSublayer(playerLayer)
        
//         // 确保视图大小变化时更新播放器图层
//         containerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
//     }
    
//     func view() -> UIView {
//         return containerView
//     }
    
//     // 更新视频图层大小
//     func updateFrame(_ frame: CGRect) {
//         containerView.frame = frame
//         playerLayer.frame = containerView.bounds
//     }
// }