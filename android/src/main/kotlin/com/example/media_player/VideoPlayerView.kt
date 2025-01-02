package com.example.media_player

import android.content.Context
import android.view.View
import android.widget.FrameLayout
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.platform.PlatformView

class VideoPlayerView(
    context: Context,
    private val player: Player
) : PlatformView {
    private val container = FrameLayout(context)
    private val playerView: PlayerView = PlayerView(
        // 在创建 PlayerView 时直接应用主题
        context.apply { 
            theme.applyStyle(R.style.CustomPlayerViewStyle, true)
        }
    ).apply {
        this.player = this@VideoPlayerView.player
        
        // 完全禁用控制器相关设置
        useController = false
        controllerAutoShow = false
        controllerHideOnTouch = false
        controllerShowTimeoutMs = 0
        showController()
        hideController()
        
        // 禁用所有控制器相关的交互
        setUseController(false)
        setControllerVisibilityListener(PlayerView.ControllerVisibilityListener {})
        setControllerHideOnTouch(false)
        
        // 其他视图设置保持不变
        setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER)
        resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
        setKeepContentOnPlayerReset(true)
    }

    init {
        // 设置 PlayerView 的布局参数
        val layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        )
        container.addView(playerView, layoutParams)
        
        // 确保视频可见
        container.visibility = View.VISIBLE
        playerView.visibility = View.VISIBLE

        // 添加播放器监听器
        player.addListener(object : Player.Listener {
            override fun onVideoSizeChanged(videoSize: VideoSize) {
                android.util.Log.d("VideoPlayerView", "Video size changed: ${videoSize.width}x${videoSize.height}")
                if (videoSize.width > 0 && videoSize.height > 0) {
                    (playerView.getChildAt(0) as? AspectRatioFrameLayout)?.setAspectRatio(
                        videoSize.width.toFloat() / videoSize.height.toFloat()
                    )
                }
            }
        })
    }

    override fun getView(): View = container

    override fun dispose() {
        playerView.player = null
        container.removeAllViews()
    }

    fun setVideoEnabled(enabled: Boolean) {
        android.util.Log.d("VideoPlayerView", "Setting video enabled: $enabled")
        container.visibility = if (enabled) View.VISIBLE else View.GONE
        if (!enabled) {
            playerView.player = null
        } else {
            playerView.player = player
            // 确保视频可见
            container.visibility = View.VISIBLE
            playerView.visibility = View.VISIBLE
            // 强制刷新布局
            container.requestLayout()
            playerView.requestLayout()
        }
    }
} 