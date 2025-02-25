// package com.example.media_player

// import android.content.Context
// import android.view.View
// import androidx.media3.common.util.UnstableApi
// import androidx.media3.exoplayer.ExoPlayer
// import androidx.media3.ui.PlayerView
// import io.flutter.plugin.common.StandardMessageCodec
// import io.flutter.plugin.platform.PlatformView
// import io.flutter.plugin.platform.PlatformViewFactory

// @UnstableApi
// class VideoPlayerViewFactory(
//     private val context: Context,
//     private val player: ExoPlayer
// ) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

//     private var videoEnabled = false
//     private var currentView: PlayerView? = null

//     override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
//         val view = VideoPlayerViewImpl(context, player)
//         view.setVideoEnabled(videoEnabled)
//         currentView = view.getView() as PlayerView
//         return view
//     }

//     fun setVideoEnabled(enabled: Boolean) {
//         videoEnabled = enabled
//         currentView?.visibility = if (enabled) View.VISIBLE else View.GONE
//     }

//     private inner class VideoPlayerViewImpl(
//         private val context: Context,
//         private val player: ExoPlayer
//     ) : PlatformView {

//         private val playerView: PlayerView = PlayerView(context).apply {
//             this.player = this@VideoPlayerViewImpl.player
//             useController = false
//             currentView = this
//         }

//         override fun getView(): View = playerView

//         override fun dispose() {
//             currentView = null
//             playerView.player = null
//         }

//         fun setVideoEnabled(enabled: Boolean) {
//             playerView.visibility = if (enabled) View.VISIBLE else View.GONE
//             if (enabled) {
//                 playerView.player = this@VideoPlayerViewImpl.player
//             } else {
//                 playerView.player = null
//             }
//         }
//     }
// } 