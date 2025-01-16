package com.example.media_player

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.support.v4.media.session.MediaSessionCompat
import androidx.core.app.NotificationCompat
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaStyleNotificationHelper
import androidx.media3.ui.PlayerNotificationManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.URL

@UnstableApi
class NotificationManager(
    private val context: Context,
    private val channelId: String = "media_playback_channel",
    private val notificationId: Int = 1000
) {
    private var notificationManager: NotificationManager? = null
    private var playerNotificationManager: PlayerNotificationManager? = null

    init {
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
                setShowBadge(false)
                // 明确设置锁屏可见性
                lockscreenVisibility = NotificationManager.IMPORTANCE_HIGH
                // 允许在锁屏上显示媒体控制
                setAllowBubbles(true)
                setSound(null, null)
                enableLights(false)
                enableVibration(false)
            }

            notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager?.createNotificationChannel(channel)
        }
    }

    fun createNotification(
        player: Player,
        mediaSession: MediaSession,
        pendingIntent: PendingIntent,
        retryCount: Int = 3
    ) {
        if (playerNotificationManager == null) {
            try {
                playerNotificationManager = PlayerNotificationManager.Builder(
                    context,
                    notificationId,
                    channelId
                )
                    .setMediaDescriptionAdapter(
                        MediaDescriptionAdapter(
                            context,
                            pendingIntent
                        )
                    )
                    .setChannelNameResourceId(R.string.notification_channel_name)
                    .setChannelDescriptionResourceId(R.string.notification_channel_description)
                    .setSmallIconResourceId(R.drawable.ic_notification)
                    .setNotificationListener(
                        object : PlayerNotificationManager.NotificationListener {
                            override fun onNotificationCancelled(notificationId: Int, dismissedByUser: Boolean) {
                                // 用户关闭通知时的处理
                                player.pause()
                            }

                            override fun onNotificationPosted(
                                notificationId: Int,
                                notification: android.app.Notification,
                                ongoing: Boolean
                            ) {
                                // 通知显示时的处理
                                Log.d("NotificationManager", "Notification posted successfully")
//                                if (ongoing) {
//                                    // 使用 FLAG_ONGOING_EVENT 确保通知持续显示
//                                    notification.flags = notification.flags or Notification.FLAG_ONGOING_EVENT
//                                    notification.flags = notification.flags or Notification.FLAG_NO_CLEAR
//                                    startForeground(notificationId, notification)
//                                }
                            }
                        }
                    )
                    .build()
                    .apply {
                        setMediaSessionToken(mediaSession.sessionCompatToken)

                        setUseNextActionInCompactView(true)
                        setUsePreviousActionInCompactView(true)
                        setUsePlayPauseActions(true)

//                        setOngoing(true)// 确保通知持续显示

                        setUseStopAction(false)
                        setUseRewindAction(false)  // 禁用快退
                        setUseFastForwardAction(false)  // 禁用快进
                        setPlayer(player)
                    }
            } catch (e: Exception) {
                Log.e("NotificationManager", "Error creating notification", e)
                if (retryCount > 0) {
                    Log.d("NotificationManager", "Retrying notification creation, attempts left: ${retryCount - 1}")
                    Handler(Looper.getMainLooper()).postDelayed({
                        createNotification(player, mediaSession, pendingIntent, retryCount - 1)
                    }, 1000)
                }
            }
        } else {
            playerNotificationManager?.setPlayer(player)
            updateNotification()
        }
    }

    fun updateNotification() {
        try {
            playerNotificationManager?.invalidate()
        } catch (e: Exception) {
            Log.e("NotificationManager", "Error updating notification", e)
        }
    }

    fun hideNotification() {
        try {
            playerNotificationManager?.setPlayer(null)
        } catch (e: Exception) {
            Log.e("NotificationManager", "Error hiding notification", e)
        }
    }

    private inner class MediaDescriptionAdapter(
        private val context: Context,
        private val pendingIntent: PendingIntent
    ) : PlayerNotificationManager.MediaDescriptionAdapter {
        private var currentArtwork: Bitmap? = null
        private var currentArtworkUri: Uri? = null

        override fun getCurrentContentTitle(player: Player): CharSequence {
            return player.mediaMetadata.title?.toString() ?: "Unknown"
        }

        override fun createCurrentContentIntent(player: Player): PendingIntent? {
            return pendingIntent
        }

        override fun getCurrentContentText(player: Player): CharSequence? {
            return player.mediaMetadata.artist?.toString()
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
                        // 加载默认图片
                        val defaultArtwork = BitmapFactory.decodeResource(
                            context.resources,
                            R.drawable.ic_notification
                        )
                        currentArtwork = defaultArtwork
                        callback.onBitmap(defaultArtwork)
                    }
                }
            }
            return currentArtwork
        }
    }
} 