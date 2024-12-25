package com.example.media_player

import android.content.Intent
import android.os.Build
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MediaPlayerService : MediaSessionService() {
    private val serviceJob = SupervisorJob()
    private val serviceScope = CoroutineScope(Dispatchers.Main + serviceJob)
    
    private lateinit var player: ExoPlayer
    private lateinit var mediaSession: MediaSession
    
    // 播放模式
    enum class PlayMode {
        ALL,    // 列表循环
        LIST,   // 列表播放一次
        ONE,    // 单曲循环
        SHUFFLE // 随机播放
    }
    
    private var currentPlayMode = PlayMode.LIST

    // 事件广播接口
    interface EventListener {
        fun onEvent(event: Map<String, Any?>)
    }
    
    // 添加 Binder 类
    inner class LocalBinder : android.os.Binder() {
        val service: MediaPlayerService
            get() = this@MediaPlayerService
    }

    private val binder = LocalBinder()

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        android.util.Log.d("MediaPlayerService", "onGetSession called for controller: ${controllerInfo.packageName}")
        if (controllerInfo.packageName == packageName) {
            return mediaSession
        }
        return null
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        stopSelf()
    }

    companion object {
        private var eventListener: EventListener? = null
        private var instance: MediaPlayerService? = null
        
        fun setEventListener(listener: EventListener?) {
            eventListener = listener
        }

        fun getInstance(): MediaPlayerService? {
            return instance
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        android.util.Log.d("MediaPlayerService", "Service onCreate")
        
        try {
            initializePlayer()
            initializeMediaSession()
            startPositionUpdates()
            android.util.Log.d("MediaPlayerService", "Service initialization completed successfully")
        } catch (e: Exception) {
            android.util.Log.e("MediaPlayerService", "Error during service initialization", e)
        }
    }

    override fun onDestroy() {
        instance = null
        positionUpdateJob?.cancel()
        mediaSession.release()
        player.release()
        serviceJob.cancel()
        super.onDestroy()
    }

    private fun initializePlayer() {
        android.util.Log.d("MediaPlayerService", "Initializing player")
        try {
            player = ExoPlayer.Builder(this)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(C.USAGE_MEDIA)
                        .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                        .build(),
                    true
                )
                .setHandleAudioBecomingNoisy(true)  // 处理耳机拔出等情况
                .setWakeMode(C.WAKE_MODE_NETWORK)   // 保持网络唤醒
                .build().apply {
                    // 设置默认的播放模式
                    repeatMode = Player.REPEAT_MODE_OFF
                    shuffleModeEnabled = false
                    
                    // 设置视频输出
                    setVideoScalingMode(C.VIDEO_SCALING_MODE_SCALE_TO_FIT)  // 设置视频缩放模式
                    
                    // 添加播放器监听
                    addListener(playerListener)
                    android.util.Log.d("MediaPlayerService", "Player initialized with listener")
                }
        } catch (e: Exception) {
            android.util.Log.e("MediaPlayerService", "Error initializing player", e)
            throw e
        }
    }

    private fun initializeMediaSession() {
        android.util.Log.d("MediaPlayerService", "Initializing MediaSession")
        mediaSession = MediaSession.Builder(this, player)
            .setCallback(mediaSessionCallback)
            .setId("MediaPlayerService")  // 设置唯一标识符
            .build()
        android.util.Log.d("MediaPlayerService", "MediaSession initialized successfully")
    }

    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            // 通知播放状态变化
            val state = when (playbackState) {
                Player.STATE_IDLE -> "none"
                Player.STATE_BUFFERING -> "loading"
                Player.STATE_READY -> "ready"
                Player.STATE_ENDED -> "completed"
                else -> "unknown"
            }
            android.util.Log.d("MediaPlayerService", "Playback state changed to: $state")
            notifyPlaybackStateChanged(state)
            
            // 如果播放结束，根据播放模式处理
            if (playbackState == Player.STATE_ENDED) {
                handlePlaybackCompletion()
            }
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            // 通知媒体项变化
            mediaItem?.let { 
                android.util.Log.d("MediaPlayerService", "Media item changed: ${it.mediaId}")
                notifyMediaItemChanged(it) 
            }
        }

        override fun onTimelineChanged(timeline: Timeline, reason: Int) {
            if (reason != Player.TIMELINE_CHANGE_REASON_PLAYLIST_CHANGED) {
                return
            }
            notifyPlaylistChanged()
        }

        override fun onPositionDiscontinuity(
            oldPosition: Player.PositionInfo,
            newPosition: Player.PositionInfo,
            reason: Int
        ) {
            // 通知播放位置变化
            notifyPositionChanged(newPosition.positionMs)
        }
        
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            // 通知播放状态变化
            val state = if (isPlaying) "playing" else "paused"
            notifyPlaybackStateChanged(state)
        }
        
        override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
            // 通知错误
            notifyError(error.message ?: "Unknown error")
            // 尝试恢复播放
            handlePlaybackError(error)
        }
        
        override fun onIsLoadingChanged(isLoading: Boolean) {
            // 通知缓冲状态
            notifyBufferingChanged(isLoading)
            
            // 如果不在缓冲状态，发送缓冲进度
            if (!isLoading) {
                notifyBufferProgress()
            }
        }

        override fun onVideoSizeChanged(videoSize: androidx.media3.common.VideoSize) {
            // 通知视频尺寸变化
            val event = mapOf(
                "type" to "videoSizeChanged",
                "data" to mapOf(
                    "width" to videoSize.width,
                    "height" to videoSize.height,
                    "unappliedRotationDegrees" to videoSize.unappliedRotationDegrees,
                    "pixelWidthHeightRatio" to videoSize.pixelWidthHeightRatio
                )
            )
            android.util.Log.d("MediaPlayerService", "Video size changed: ${videoSize.width}x${videoSize.height}")
            broadcastEvent(event)
        }
    }

    private val mediaSessionCallback = object : MediaSession.Callback {
        override fun onAddMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: List<MediaItem>
        ): ListenableFuture<List<MediaItem>> {
            return super.onAddMediaItems(mediaSession, controller, mediaItems)
        }

        override fun onConnect(
            session: MediaSession,
            controller: MediaSession.ControllerInfo
        ): MediaSession.ConnectionResult {
            return super.onConnect(session, controller)
        }
    }

    // 播放模式控制
    fun setPlayMode(mode: PlayMode) {
        android.util.Log.d("MediaPlayerService", "Setting play mode to: $mode")
        currentPlayMode = mode
        when (mode) {
            PlayMode.ALL -> {
                player.repeatMode = Player.REPEAT_MODE_ALL
                player.shuffleModeEnabled = false
            }
            PlayMode.LIST -> {
                player.repeatMode = Player.REPEAT_MODE_OFF
                player.shuffleModeEnabled = false
            }
            PlayMode.ONE -> {
                player.repeatMode = Player.REPEAT_MODE_ONE
                player.shuffleModeEnabled = false
            }
            PlayMode.SHUFFLE -> {
                player.repeatMode = Player.REPEAT_MODE_ALL
                player.shuffleModeEnabled = true
            }
        }
        // 发送播��模式变化事件
        notifyPlayModeChanged(mode)
    }
    
    fun getPlayMode(): PlayMode = currentPlayMode
    
    // 通知方法
    private fun notifyPlaybackStateChanged(state: String) {
        val event = mapOf(
            "type" to "playbackStateChanged",
            "data" to state
        )
        broadcastEvent(event)
    }
    
    private fun notifyMediaItemChanged(mediaItem: MediaItem) {
        val event = mapOf(
            "type" to "mediaItemChanged",
            "data" to mapOf(
                "id" to mediaItem.mediaId,
                "title" to mediaItem.mediaMetadata.title,
                "artist" to mediaItem.mediaMetadata.artist,
                "album" to mediaItem.mediaMetadata.displayTitle,
                "artworkUrl" to mediaItem.mediaMetadata.artworkUri?.toString(),
                "url" to mediaItem.localConfiguration?.uri?.toString()
            )
        )
        broadcastEvent(event)
    }
    
    private fun notifyPositionChanged(positionMs: Long) {
        val event = mapOf(
            "type" to "positionChanged",
            "data" to positionMs
        )
        broadcastEvent(event)
    }

    private var positionUpdateJob: kotlinx.coroutines.Job? = null

    private fun handlePlaybackError(error: androidx.media3.common.PlaybackException) {
        when (error.errorCode) {
            androidx.media3.common.PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
            androidx.media3.common.PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT -> {
                // 网络错误，尝试重新连接
                player.prepare()
            }
            androidx.media3.common.PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW -> {
                // 直播流错误，尝试重新加载
                player.seekToDefaultPosition()
                player.prepare()
            }
            else -> {
                // 其他错误，尝试跳到下一首
                if (currentPlayMode != PlayMode.ONE) {
                    player.seekToNextMediaItem()
                }
            }
        }
    }
    
    private fun handlePlaybackCompletion() {
        when (currentPlayMode) {
            PlayMode.ONE -> {
                // 单曲循环：重新播放当前曲
                player.seekTo(0)
                player.play()
            }
            PlayMode.ALL -> {
                // 列表循环：如果是最一首，则从头开始
                if (!player.hasNextMediaItem()) {
                    player.seekToDefaultPosition(0)
                    player.play()
                }
            }
            PlayMode.LIST -> {
                // 列表播放：如果是最后一首，则停止播放
                if (!player.hasNextMediaItem()) {
                    player.stop()
                    notifyPlaybackStateChanged("completed")
                }
            }
            PlayMode.SHUFFLE -> {
                // 随机播放：继续播放下一首随机歌曲
                if (!player.hasNextMediaItem()) {
                    player.seekToDefaultPosition(0)
                }
                player.play()
            }
        }
    }
    
    // 通知方法
    private fun notifyError(message: String) {
        val event = mapOf(
            "type" to "error",
            "data" to message
        )
        broadcastEvent(event)
    }
    
    private fun notifyBufferingChanged(isBuffering: Boolean) {
        val event = mapOf(
            "type" to "bufferingChanged",
            "data" to isBuffering
        )
        broadcastEvent(event)
    }
    
    private fun notifyBufferProgress() {
        val duration = player.duration
        if (duration > 0) {
            val bufferedPosition = player.bufferedPosition
            val progress = (bufferedPosition.toFloat() / duration.toFloat()).coerceIn(0f, 1f)
            val event = mapOf(
                "type" to "bufferChanged",
                "data" to progress
            )
            broadcastEvent(event)
        }
    }

    private fun startPositionUpdates() {
        positionUpdateJob?.cancel()
        positionUpdateJob = serviceScope.launch {
            while (true) {
                if (player.isPlaying) {
                    // 发送播放位置
                    notifyPositionChanged(player.currentPosition)
                    // 发送时长
                    notifyDurationChanged(player.duration)
                }
                kotlinx.coroutines.delay(1000) // 每秒更新一次
            }
        }
    }

    private fun notifyDurationChanged(durationMs: Long) {
        val event = mapOf(
            "type" to "durationChanged",
            "data" to durationMs
        )
        broadcastEvent(event)
    }

    private fun notifyPlayModeChanged(mode: PlayMode) {
        val modeString = when (mode) {
            PlayMode.ALL -> "all"
            PlayMode.LIST -> "list"
            PlayMode.ONE -> "one"
            PlayMode.SHUFFLE -> "shuffle"
        }
        val event = mapOf(
            "type" to "playModeChanged",
            "data" to modeString
        )
        android.util.Log.d("MediaPlayerService", "Broadcasting play mode changed event: $modeString")
        broadcastEvent(event)
    }

    // 自定义绑定方法
    fun getCustomBinder(): android.os.IBinder {
        return binder
    }

    private fun broadcastEvent(event: Map<String, Any?>) {
        android.util.Log.d("MediaPlayerService", "Broadcasting event: ${event["type"]}")
        eventListener?.onEvent(event)
    }

    private fun notifyPlaylistChanged() {
        val mediaItems = mutableListOf<MediaItem>()
        for (i in 0 until player.mediaItemCount) {
            player.getMediaItemAt(i)?.let { mediaItems.add(it) }
        }
        
        val playlistData = mediaItems.map { mediaItem ->
            mapOf(
                "id" to mediaItem.mediaId,
                "title" to mediaItem.mediaMetadata.title,
                "artist" to mediaItem.mediaMetadata.artist,
                "album" to mediaItem.mediaMetadata.displayTitle,
                "artworkUrl" to mediaItem.mediaMetadata.artworkUri?.toString(),
                "url" to mediaItem.localConfiguration?.uri?.toString()
            )
        }
        
        val event = mapOf(
            "type" to "playlistChanged",
            "data" to playlistData
        )
        android.util.Log.d("MediaPlayerService", "Broadcasting playlist changed event with ${playlistData.size} items")
        broadcastEvent(event)
    }
} 