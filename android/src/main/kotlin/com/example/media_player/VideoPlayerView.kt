// package com.example.media_player

// import android.content.Context
// import android.view.View
// import android.widget.FrameLayout
// import androidx.media3.common.Player
// import androidx.media3.common.VideoSize
// import androidx.media3.ui.AspectRatioFrameLayout
// import androidx.media3.ui.PlayerView
// import io.flutter.plugin.platform.PlatformView

// class VideoPlayerView(
//     context: Context,
//     private val player: Player
// ) : PlatformView {
//     private val container = FrameLayout(context)
//     private val playerView: PlayerView = PlayerView(
//         // Apply the theme directly when creating the PlayerView
//         context.apply {
//             theme.applyStyle(R.style.CustomPlayerViewStyle, true)
//         }
//     ).apply {
//         this.player = this@VideoPlayerView.player

//         // Disable controller-related settings
//         useController = false
//         controllerAutoShow = false
//         controllerHideOnTouch = false
//         controllerShowTimeoutMs = 0
//         setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER)
//         resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
//         setKeepContentOnPlayerReset(true)
//     }

//     init {
//         val layoutParams = FrameLayout.LayoutParams(
//             FrameLayout.LayoutParams.MATCH_PARENT,
//             FrameLayout.LayoutParams.MATCH_PARENT
//         )
//         container.addView(playerView, layoutParams)
//         container.visibility = View.VISIBLE
//         playerView.visibility = View.VISIBLE

//         // Add a listener to adjust the aspect ratio when the video size changes.
//         player.addListener(object : Player.Listener {
//             override fun onVideoSizeChanged(videoSize: VideoSize) {
//                 if (videoSize.width > 0 && videoSize.height > 0) {
//                     // 计算宽高比
//                     val aspectRatio = videoSize.width.toFloat() / videoSize.height.toFloat()

//                     // 更新 PlayerView 的 LayoutParams
//                     val layoutParams = playerView.layoutParams as FrameLayout.LayoutParams
//                     layoutParams.width = FrameLayout.LayoutParams.MATCH_PARENT
//                     layoutParams.height = (layoutParams.width / aspectRatio).toInt() // 根据宽度和宽高比计算高度
//                     playerView.layoutParams = layoutParams
//                 }
//             }
//         })
//     }

//     override fun getView(): View = container

//     override fun dispose() {
//         playerView.player = null // Release the player
//         container.removeAllViews()
//     }

//     fun setVideoEnabled(enabled: Boolean) {
//         container.visibility = if (enabled) View.VISIBLE else View.GONE
//         playerView.player = if (enabled) player else null // Set/unset player
//         if (enabled) {
//             // Ensure visibility and refresh layout
//             container.visibility = View.VISIBLE
//             playerView.visibility = View.VISIBLE
//             container.requestLayout()
//             playerView.requestLayout()
//         }
//     }
// } 