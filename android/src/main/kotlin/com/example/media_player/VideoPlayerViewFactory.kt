package com.example.media_player

import android.content.Context
import androidx.media3.common.Player
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class VideoPlayerViewFactory(
    private val context: Context,
    private val player: Player
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    
    private var currentView: VideoPlayerView? = null
    
    override fun create(context: Context?, viewId: Int, args: Any?): PlatformView {
        android.util.Log.d("VideoPlayerViewFactory", "Creating new video view with ID: $viewId")
        
        // 如果已经有视图，先销毁它
        currentView?.dispose()
        
        return VideoPlayerView(this.context, player).also {
            currentView = it
            // 默认启用视频显示
            it.setVideoEnabled(true)
            android.util.Log.d("VideoPlayerViewFactory", "Video view created and enabled")
            
            // 检查播放器状态
            val videoSize = player.videoSize
            android.util.Log.d("VideoPlayerViewFactory", "Current video size: ${videoSize.width}x${videoSize.height}")
            
            // 如果当前有视频在播放，确保它显示出来
            if (player.isPlaying && videoSize.width > 0 && videoSize.height > 0) {
                android.util.Log.d("VideoPlayerViewFactory", "Video is currently playing, ensuring it's visible")
                it.setVideoEnabled(true)
            }
        }
    }
    
    fun setVideoEnabled(enabled: Boolean) {
        android.util.Log.d("VideoPlayerViewFactory", "Setting video enabled: $enabled")
        currentView?.setVideoEnabled(enabled)
    }
    
    fun dispose() {
        android.util.Log.d("VideoPlayerViewFactory", "Disposing video view")
        currentView?.dispose()
        currentView = null
    }
} 