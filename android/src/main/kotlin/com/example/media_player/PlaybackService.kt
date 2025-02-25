package com.example.media_player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaSession
import androidx.media3.ui.PlayerNotificationManager
import androidx.media3.common.util.Util
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.URL
import androidx.media3.common.MediaItem

@UnstableApi
class PlaybackService : Service() {
    private var mediaSession: MediaSession? = null
    private var playerNotificationManager: PlayerNotificationManager? = null
    private val notificationId = 1
    private val channelId = "media_player_channel"
    private val binder = LocalBinder()

    inner class LocalBinder : Binder() {
        fun getService(): PlaybackService = this@PlaybackService
    }

    override fun onBind(intent: Intent): IBinder {
        return binder
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Media Playback",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Media playback controls"
                setShowBadge(false) // 通常建议用于媒体播放
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    fun setupNotification(
        session: MediaSession,
        activityIntent: PendingIntent?
    ) {
        mediaSession = session

        playerNotificationManager = PlayerNotificationManager.Builder(
            this,
            notificationId,
            channelId
        )
        .setMediaDescriptionAdapter(MediaDescriptionAdapter(this, activityIntent))
        .setNotificationListener(object : PlayerNotificationManager.NotificationListener {
            override fun onNotificationCancelled(notificationId: Int, dismissedByUser: Boolean) {
                // 当通知被取消时，停止播放和服务。
                session.player.pause()
                stopForeground(true)
                stopSelf()
            }

            override fun onNotificationPosted(
                notificationId: Int,
                notification: Notification,
                ongoing: Boolean
            ) {
                // 当通知发布时，在前台启动服务。
                if (ongoing) {
                    startForeground(notificationId, notification)
                } else {
                    stopForeground(false) // 保留通知，但删除前台状态
                }
            }
        })
        .build()
        .apply {
            setPlayer(session.player)
            setMediaSessionToken(session.sessionCompatToken) // 非常重要
            setUseNextAction(true)
            setUsePreviousAction(true)
            setUsePlayPauseActions(true)
            setUseFastForwardAction(false) // 通常禁用这些
            setUseRewindAction(false)
            setUseStopAction(true) // 允许从通知停止
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // 使用 START_STICKY 以确保服务在被系统终止时重新启动。
        return START_STICKY
    }

    override fun onDestroy() {
        playerNotificationManager?.setPlayer(null)
        mediaSession?.release()
        mediaSession = null
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // 不要在此时停止服务。让播放继续。
        // 仅当播放器未播放且播放列表为空时才停止。
        val player = mediaSession?.player
        if (player == null || !player.playWhenReady || player.mediaItemCount == 0) {
            stopSelf()
        }
    }

    private inner class MediaDescriptionAdapter(
        private val context: Context,
        private val pendingIntent: PendingIntent?
    ) : PlayerNotificationManager.MediaDescriptionAdapter {

        private var currentArtwork: Bitmap? = null
        private var currentArtworkUri: Uri? = null

        override fun getCurrentContentTitle(player: Player): CharSequence {
            return player.mediaMetadata.title ?: "Unknown Title"
        }

        override fun createCurrentContentIntent(player: Player): PendingIntent? {
            return pendingIntent
        }

        override fun getCurrentContentText(player: Player): CharSequence? {
            return player.mediaMetadata.artist ?: "Unknown Artist"
        }


        override fun getCurrentLargeIcon(
            player: Player,
            callback: PlayerNotificationManager.BitmapCallback
        ): Bitmap? {
            val artworkUri = player.mediaMetadata.artworkUri

            if (artworkUri == currentArtworkUri) {
                return currentArtwork
            }

            currentArtworkUri = artworkUri
            currentArtwork = null // 重置以避免显示旧的 artwork

            if (artworkUri != null) {
                CoroutineScope(Dispatchers.IO).launch {
                    try {
                        val bitmap = withContext(Dispatchers.IO) {
                            URL(artworkUri.toString()).openStream().use { stream ->
                                BitmapFactory.decodeStream(stream)
                            }
                        }
                        currentArtwork = bitmap
                        callback.onBitmap(bitmap)

                    } catch (e: Exception) {
                        Log.e("PlaybackService", "Error loading artwork: ${e.message}")
                        // 加载默认/占位符图像
                        val defaultBitmap = BitmapFactory.decodeResource(context.resources, R.drawable.ic_notification) // 替换为您的占位符
                        currentArtwork = defaultBitmap
                        callback.onBitmap(defaultBitmap)
                    }
                }
            } else {
                // 如果 artworkUri 为 null，也使用默认图像
                val defaultBitmap = BitmapFactory.decodeResource(context.resources, R.drawable.ic_notification) // 替换为您的占位符
                currentArtwork = defaultBitmap
                callback.onBitmap(defaultBitmap)
            }

            return null // 最初返回 null；位图将通过回调提供
        }
    }

    fun updateNotification(mediaItem: MediaItem) {
        // No need to do anything here.  The PlayerNotificationManager
        // will automatically update when the player's state changes.
        // We just need this method signature for the plugin to call.
    }

    companion object {
        fun startService(context: Context) {
            val intent = Intent(context, PlaybackService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Util.startForegroundService(context, intent)
            } else {
                context.startService(intent)
            }
        }
    }
} 