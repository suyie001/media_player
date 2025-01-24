import Flutter
import UIKit
import AVFoundation  // 添加这行

public class MediaPlayerPlugin: NSObject, FlutterPlugin {
    private let mediaPlayer = MediaPlayerHandler.shared
    private var videoViewFactory: MediaPlayerVideoViewFactory?
    private var eventSink: FlutterEventSink?
    private var registrar: FlutterPluginRegistrar?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "media_player", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "media_player_events", binaryMessenger: registrar.messenger())
        
        let instance = MediaPlayerPlugin()
        instance.registrar = registrar
        
        // 在插件初始化时就创建并注册视图工厂
        instance.videoViewFactory = MediaPlayerVideoViewFactory(player: instance.mediaPlayer.player)
        registrar.register(instance.videoViewFactory!, withId: "media_player_video_view")
        
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "showVideoView":
            // 只需要处理显示/隐藏逻辑，不需要再注册视图工厂
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

        case "updateAt":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int,
                  let mediaItem = args["mediaItem"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "Index and mediaItem are required",
                                  details: nil))
                return
            }
            mediaPlayer.updateAt(index, mediaItem: mediaItem)
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
            
        case "updateCurrentUrl":
            guard let args = call.arguments as? [String: Any],
                  let url = args["url"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "URL is required",
                                  details: nil))
                return
            }
            mediaPlayer.updateCurrentUrl(url)
            result(nil)

        case "setSpeed":
            guard let args = call.arguments as? [String: Any],
                  let speed = args["speed"] as? Double else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "Speed is required",
                                  details: nil))
                return
            }
            mediaPlayer.setSpeed(speed)
            result(nil)

        
            
        case "startPictureInPicture":
            mediaPlayer.startPictureInPicture()
            result(nil)
            
        case "stopPictureInPicture":
            mediaPlayer.stopPictureInPicture()
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
    private let containerView: UIView
    private var eventSink: FlutterEventSink?
    private var playerObservation: NSKeyValueObservation?
    private let mediaPlayer: MediaPlayerHandler
    
    init(frame: CGRect, player: AVPlayer, eventSink: FlutterEventSink?) {
        containerView = UIView(frame: frame)
        self.eventSink = eventSink
        self.mediaPlayer = MediaPlayerHandler.shared // 需要添加一个 shared 实例
        super.init()
        
        // 设置后台播放
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        
        // 允许画中画和后台播放
        player.allowsExternalPlayback = true
        player.preventsDisplaySleepDuringVideoPlayback = true
        
        setupView()
        setupObservers()
    }
    
    private func setupView() {
        // 确保视图背景透明
        containerView.backgroundColor = .clear
        
        // 设置自动布局
        containerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // 配置播放器图层
        if let playerLayer = mediaPlayer.getPlayerLayer() {
            playerLayer.frame = containerView.bounds
            playerLayer.videoGravity = .resizeAspect
            
            // 添加到视图层级
            containerView.layer.addSublayer(playerLayer)
        }
    }
    
    private func setupObservers() {
        // 观察播放器图层的就绪状态
        if let playerLayer = mediaPlayer.getPlayerLayer() {
            playerObservation = playerLayer.observe(\.isReadyForDisplay) { [weak self] layer, _ in
                if layer.isReadyForDisplay {
                    self?.handlePlayerReady()
                }
            }
        }
        
        // 监听应用进入后台
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        // 监听应用进入前台
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
        // 监听方向变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
    
    @objc private func handleEnterBackground() {
        // 确保后台播放继续
        try? AVAudioSession.sharedInstance().setActive(true)
        mediaPlayer.player.play()
    }
    
    @objc private func handleEnterForeground() {
        // 更新视图布局
        updateVideoLayout()
    }
    
    private func handlePlayerReady() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateVideoLayout()
            self.eventSink?(["type": "videoReady"])
        }
    }
    
    @objc private func orientationChanged() {
        updateVideoLayout()
    }
    
    private func updateVideoLayout() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let playerLayer = self.mediaPlayer.getPlayerLayer() else { return }
            
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            playerLayer.frame = self.containerView.bounds
            CATransaction.commit()
        }
    }
    
    func view() -> UIView {
        return containerView
    }
    
    deinit {
        playerObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}