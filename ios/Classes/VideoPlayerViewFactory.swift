// import Flutter
// import AVFoundation

// class VideoPlayerViewFactory: NSObject, FlutterPlatformViewFactory {
//     private let mediaPlayer: MediaPlayerHandler
    
//     init(mediaPlayer: MediaPlayerHandler) {
//         self.mediaPlayer = mediaPlayer
//         super.init()
//     }
    
//     func create(
//         withFrame frame: CGRect,
//         viewIdentifier viewId: Int64,
//         arguments args: Any?
//     ) -> FlutterPlatformView {
//         return VideoPlayerView(
//             frame: frame,
//             player: mediaPlayer.player,
//             mediaPlayer: mediaPlayer
//         )
//     }
    
//     // 支持创建参数编码
//     public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
//         return FlutterStandardMessageCodec.sharedInstance()
//     }
// } 