// import Flutter
// import AVFoundation

// class VideoPlayerViewFactory: NSObject, FlutterPlatformViewFactory {
//     private let player: AVPlayer
    
//     init(player: AVPlayer) {
//         self.player = player
//         super.init()
//     }
    
//     func create(
//         withFrame frame: CGRect,
//         viewIdentifier viewId: Int64,
//         arguments args: Any?
//     ) -> FlutterPlatformView {
//         return VideoPlayerView(
//             frame: frame,
//             viewIdentifier: viewId,
//             player: player
//         )
//     }
    
//     // 支持创建参数编码
//     public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
//         return FlutterStandardMessageCodec.sharedInstance()
//     }
// }

// class VideoPlayerView: NSObject, FlutterPlatformView {
//     private let playerLayer: AVPlayerLayer
//     private let containerView: UIView
//     private var playerObservation: Any?
    
//     init(frame: CGRect, viewIdentifier: Int64, player: AVPlayer) {
//         containerView = UIView(frame: frame)
//         playerLayer = AVPlayerLayer(player: player)
//         super.init()
        
//         setupView()
//         setupObservers()
//     }
    
//     private func setupView() {
//         // 配置容器视图
//         containerView.backgroundColor = .black
//         containerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
//         // 配置播放器图层
//         playerLayer.frame = containerView.bounds
//         playerLayer.videoGravity = .resizeAspect
//         containerView.layer.addSublayer(playerLayer)
        
//         // 添加手势识别器支持全屏
//         let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
//         containerView.addGestureRecognizer(tapGesture)
//     }
    
//     private func setupObservers() {
//         // 监听播放器图层的绑定状态
//         playerObservation = playerLayer.observe(\.isReadyForDisplay) { [weak self] layer, _ in
//             if layer.isReadyForDisplay {
//                 self?.handlePlayerReady()
//             }
//         }
        
//         // 监听设备方向变化
//         NotificationCenter.default.addObserver(
//             self,
//             selector: #selector(orientationChanged),
//             name: UIDevice.orientationDidChangeNotification,
//             object: nil
//         )
//     }
    
//     private func handlePlayerReady() {
//         // 可以在这里添加视频准备就绪后的处理逻辑
//         updateVideoLayout()
//     }
    
//     @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
//         // 处理点击事件，可以在这里实现全屏切换等功能
//     }
    
//     @objc private func orientationChanged() {
//         updateVideoLayout()
//     }
    
//     private func updateVideoLayout() {
//         CATransaction.begin()
//         CATransaction.setAnimationDuration(0.25)
//         playerLayer.frame = containerView.bounds
//         CATransaction.commit()
//     }
    
//     func view() -> UIView {
//         return containerView
//     }
    
//     func updateFrame(_ frame: CGRect) {
//         containerView.frame = frame
//         updateVideoLayout()
//     }
    
//     deinit {
//         if let observation = playerObservation {
//             observation.invalidate()
//         }
//         NotificationCenter.default.removeObserver(self)
//     }
// }