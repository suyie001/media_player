package com.example.media_player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.os.Bundle
import androidx.core.app.NotificationCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.Player.RepeatMode
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.MediaStyleNotificationHelper
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
    private lateinit var notificationManager: NotificationManager
    
    private val channelId = "media_player_channel"
    private val notificationId = 1
    
    // 播放模式
    enum class PlayMode {
        ALL,    // 列表循环
        LIST,   // 列表播放一次
        ONE,    // 单曲循环
        SHUFFLE // 随机播放
    }
    
    private var currentPlayMode = PlayMode.LIST

    override fun onCreate() {
        super.onCreate()
        android.util.Log.d("MediaPlayerService", "Service onCreate")
        initializePlayer()
        initializeMediaSession()
        initializeNotificationManager()
        android.util.Log.d("MediaPlayerService", "Service initialization completed")
    }

    private fun initializePlayer() {
        android.util.Log.d("MediaPlayerService", "Initializing player")
        player = ExoPlayer.Builder(this)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .build(),
                true
            )
            .build().apply {
                // 设置默认的播放模式
                repeatMode = Player.REPEAT_MODE_OFF
                shuffleModeEnabled = false
                
                // 添加播放器监听
                addListener(playerListener)
                android.util.Log.d("MediaPlayerService", "Player initialized with listener")
            }
    }

    private fun initializeMediaSession() {
        mediaSession = MediaSession.Builder(this, player)
            .setCallback(mediaSessionCallback)
            .build()
    }

    private fun initializeNotificationManager() {
        notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Media Player",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Media player controls"
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            updateNotification()
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
            updateNotification()
            // 通知媒体项变化
            mediaItem?.let { 
                android.util.Log.d("MediaPlayerService", "Media item changed: ${it.mediaId}")
                notifyMediaItemChanged(it) 
            }
        }
        
        override fun onPositionDiscontinuity(
            oldPosition: Player.PositionInfo,
            newPosition: Player.PositionInfo,
            reason: Int
        ) {
            // 通知播放位置变化
            notifyPositionChanged(newPosition.positionMs)
        }
        
        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
            // 通知播放/暂停状态变化
            val state = if (playWhenReady) "playing" else "paused"
            notifyPlaybackStateChanged(state)
        }
        
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            updateNotification()
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
        }
        
        override fun onLoadingChanged(isLoading: Boolean) {
            // 通知缓冲状态（兼容旧版本）
            notifyBufferingChanged(isLoading)
        }
        
        override fun onAvailableCommandsChanged(availableCommands: Player.Commands) {
            // 更新可用的控制命令
            updatePlayerControls(availableCommands)
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

    private fun updateNotification() {
        val notification = buildNotification()
        notificationManager.notify(notificationId, notification)
    }

    private fun buildNotification(): Notification {
        val mediaItem = player.currentMediaItem
        val title = mediaItem?.mediaMetadata?.title ?: "Unknown"
        val artist = mediaItem?.mediaMetadata?.artist ?: "Unknown"
        
        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(artist)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOnlyAlertOnce(true)
            .setOngoing(player.isPlaying)

        // 添加媒体样式
        val mediaStyle = MediaStyleNotificationHelper.MediaStyle(mediaSession)
        builder.setStyle(mediaStyle)

        return builder.build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return mediaSession
    }
    
    // 播放模式控制
    fun setPlayMode(mode: PlayMode) {
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
    }
    
    fun getPlayMode(): PlayMode = currentPlayMode
    
    // 通知方法
    private fun notifyPlaybackStateChanged(state: String) {
        mediaSession.player.currentMediaItem?.let { mediaItem ->
            val event = mapOf(
                "type" to "playbackStateChanged",
                "data" to state
            )
            // 通过 EventChannel 发送事件
        }
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
        // 通过 EventChannel 发送事件
    }
    
    private fun notifyPositionChanged(positionMs: Long) {
        val event = mapOf(
            "type" to "positionChanged",
            "data" to positionMs
        )
        // 通过 EventChannel 发送事件
    }

    override fun onDestroy() {
        mediaSession.release()
        player.release()
        serviceJob.cancel()
        super.onDestroy()
    }
    
    // 获取播放器实例
    fun getPlayer(): ExoPlayer = player
    
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
                // 单曲循环：重新播放当前歌曲
                player.seekTo(0)
                player.play()
            }
            PlayMode.ALL -> {
                // 列表循环：如果是最后一首，则从头开始
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
    
    private fun updatePlayerControls(commands: Player.Commands) {
        // 更新通知栏控制按钮状态
        val notification = buildNotification()
        notificationManager.notify(notificationId, notification)
    }
    
    // 通知方法
    private fun notifyError(message: String) {
        val event = mapOf(
            "type" to "error",
            "data" to message
        )
        // 通过 EventChannel 发送事件
    }
    
    private fun notifyBufferingChanged(isBuffering: Boolean) {
        val event = mapOf(
            "type" to "bufferingChanged",
            "data" to isBuffering
        )
        // 通过 EventChannel 发送事件
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
            // 通过 EventChannel 发送事件
        }
    }
} 