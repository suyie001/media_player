package com.example.media_player

import android.content.Context
import android.view.View
import android.widget.FrameLayout
import androidx.media3.common.Player
import androidx.media3.ui.PlayerView
import io.flutter.plugin.platform.PlatformView

class VideoPlayerViewFactory(
    private val context: Context,
    private val player: Player
) : io.flutter.plugin.platform.PlatformViewFactory(io.flutter.plugin.common.StandardMessageCodec.INSTANCE) {
    
    override fun create(context: Context?, viewId: Int, args: Any?): PlatformView {
        return VideoPlayerView(this.context, player)
    }
}

class VideoPlayerView(
    context: Context,
    private val player: Player
) : PlatformView {
    
    private val playerView: PlayerView
    private val container: FrameLayout
    
    init {
        container = FrameLayout(context)
        playerView = PlayerView(context).apply {
            useController = false // 不使用默认控制器
            this.player = this@VideoPlayerView.player
        }
        container.addView(playerView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))
    }
    
    override fun getView(): View {
        return container
    }
    
    override fun dispose() {
        playerView.player = null
    }
} 