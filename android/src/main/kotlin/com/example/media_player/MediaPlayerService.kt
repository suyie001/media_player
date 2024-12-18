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

    override fun onCreate() {
        super.onCreate()
        initializePlayer()
        initializeMediaSession()
        initializeNotificationManager()
    }

    private fun initializePlayer() {
        player = ExoPlayer.Builder(this)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .build(),
                true
            )
            .build()
        
        player.addListener(playerListener)
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
            // 通知 Flutter 端状态变化
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            updateNotification()
            // 通知 Flutter 端媒体项变化
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
            .setOngoing(true)

        // 添加媒体样式
        val mediaStyle = MediaStyleNotificationHelper.MediaStyle(mediaSession)
        builder.setStyle(mediaStyle)

        return builder.build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return mediaSession
    }

    override fun onDestroy() {
        mediaSession.release()
        player.release()
        serviceJob.cancel()
        super.onDestroy()
    }
} 