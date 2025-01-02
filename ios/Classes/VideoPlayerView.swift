// import Flutter
// import AVFoundation

// class VideoPlayerView: NSObject, FlutterPlatformView {
//     private let containerView: UIView
//     private let mediaPlayer: MediaPlayerHandler
    
//     init(frame: CGRect, player: AVPlayer, mediaPlayer: MediaPlayerHandler) {
//         containerView = UIView(frame: frame)
//         self.mediaPlayer = mediaPlayer
//         super.init()
        
//         setupView()
//     }
    
//     private func setupView() {
//         containerView.backgroundColor = .clear
        
//         // 获取播放器图层
//         let playerLayer = mediaPlayer.attachPlayerLayer()
//         playerLayer.frame = containerView.bounds
//         containerView.layer.addSublayer(playerLayer)
//     }
    
//     func view() -> UIView {
//         return containerView
//     }
    
//     deinit {
//         // 清理播放器图层
//         mediaPlayer.detachPlayerLayer()
//     }
// }