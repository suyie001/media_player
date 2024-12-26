package com.example.media_player

import android.app.Activity
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.NonNull
import androidx.media3.common.*
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionCommands
import androidx.media3.session.SessionResult
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import com.google.common.util.concurrent.ListenableFuture
import io.flutter.embedding.engine.FlutterEngine
import com.google.common.collect.ImmutableList

@UnstableApi
class MediaPlayerPlugin : FlutterPlugin, ActivityAware, MethodCallHandler {
    private lateinit var context: Context
    private var activity: Activity? = null
    private lateinit var messenger: BinaryMessenger
    private var mediaSession: MediaSession? = null
    private var player: ExoPlayer? = null
    private val serviceJob = SupervisorJob()
    private val serviceScope = CoroutineScope(Dispatchers.Main + serviceJob)
    private var videoViewFactory: VideoPlayerViewFactory? = null
    private var flutterEngine: FlutterEngine? = null

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel

    private var playbackService: PlaybackService? = null
    private var isServiceBound = false

    private var serviceConnection = object : android.content.ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: android.os.IBinder?) {
            if (service is PlaybackService.LocalBinder) {
                playbackService = service.getService()
                isServiceBound = true
                player?.currentMediaItem?.let { setupNotification(it) }
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            playbackService = null
            isServiceBound = false
        }
    }

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        messenger = binding.binaryMessenger
        flutterEngine = binding.flutterEngine
        methodChannel = MethodChannel(messenger, "media_player")
        eventChannel = EventChannel(messenger, "media_player_events")
        
        Handler(Looper.getMainLooper()).post {
            initializePlayer()
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        // 注册视频视图工厂
        videoViewFactory = player?.let { VideoPlayerViewFactory(context, it) }
        videoViewFactory?.let {
            flutterEngine?.platformViewsController?.registry
                ?.registerViewFactory("media_player_video_view", it)
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        if (isServiceBound) {
            try {
                context.unbindService(serviceConnection)
            } catch (e: Exception) {
                Log.e("MediaPlayerPlugin", "Error unbinding service", e)
            }
            isServiceBound = false
        }
        activity = null
    }

    private fun initializePlayer() {
        try {
            // 创建 ExoPlayer 实例
            player = ExoPlayer.Builder(context)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(C.USAGE_MEDIA)
                        .setContentType(C.CONTENT_TYPE_MUSIC)
                        .build(),
                    true
                )
                .setHandleAudioBecomingNoisy(true)
                .build()

            // 添加播放器监听
            player?.addListener(playerListener)

            // �� MediaSession
            mediaSession = player?.let { 
                MediaSession.Builder(context, it)
                    .setCallback(mediaSessionCallback)
                    .setId("MediaPlayerService")
                    .build()
            }

            // 设置方法通道
            methodChannel.setMethodCallHandler(this)

            // 设置事件通道
            eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        } catch (e: Exception) {
            Log.e("MediaPlayerPlugin", "Failed to initialize player", e)
        }
    }

    private var eventSink: EventChannel.EventSink? = null

    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            val state = when (playbackState) {
                Player.STATE_IDLE -> "none"
                Player.STATE_BUFFERING -> "loading"
                Player.STATE_READY -> "ready"
                Player.STATE_ENDED -> "completed"
                else -> "unknown"
            }
            notifyPlaybackStateChanged(state)
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            mediaItem?.let { 
                notifyMediaItemChanged(it)
                setupNotification(it)
                notifyPlaylistChanged()
            }
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            val state = if (isPlaying) "playing" else "paused"
            notifyPlaybackStateChanged(state)
        }

        override fun onTimelineChanged(timeline: Timeline, reason: Int) {
            notifyPlaylistChanged()
        }
    }

    private val mediaSessionCallback = object : MediaSession.Callback {
        override fun onConnect(
            session: MediaSession,
            controller: MediaSession.ControllerInfo
        ): MediaSession.ConnectionResult {
            val sessionCommands = SessionCommands.Builder().build()
            
            val playerCommands = Player.Commands.Builder()
                .addAll(
                    Player.COMMAND_PLAY_PAUSE,
                    Player.COMMAND_SEEK_TO_NEXT,
                    Player.COMMAND_SEEK_TO_PREVIOUS,
                    Player.COMMAND_SEEK_TO_DEFAULT_POSITION,
                    Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM,
                    Player.COMMAND_GET_CURRENT_MEDIA_ITEM,
                    Player.COMMAND_GET_TIMELINE,
                    Player.COMMAND_GET_MEDIA_ITEMS_METADATA
                )
                .build()
                
            return MediaSession.ConnectionResult.accept(sessionCommands, playerCommands)
        }

        override fun onPlaybackResumption(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo
        ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
            val currentItems = mutableListOf<MediaItem>()
            player?.let { exoPlayer ->
                for (i in 0 until exoPlayer.mediaItemCount) {
                    exoPlayer.getMediaItemAt(i)?.let { currentItems.add(it) }
                }
            }
            
            return com.google.common.util.concurrent.Futures.immediateFuture(
                MediaSession.MediaItemsWithStartPosition(
                    currentItems,
                    player?.currentMediaItemIndex ?: 0,
                    player?.currentPosition ?: 0
                )
            )
        }
    }

    private fun notifyPlaybackStateChanged(state: String) {
        val event = mapOf(
            "type" to "playbackStateChanged",
            "data" to state
        )
        activity?.runOnUiThread {
            eventSink?.success(event)
        }
    }

    private fun notifyMediaItemChanged(mediaItem: MediaItem) {
        val event = mapOf(
            "type" to "mediaItemChanged",
            "data" to mapOf(
                "id" to mediaItem.mediaId,
                "title" to mediaItem.mediaMetadata.title?.toString(),
                "artist" to mediaItem.mediaMetadata.artist?.toString(),
                "album" to mediaItem.mediaMetadata.displayTitle?.toString(),
                "artworkUrl" to mediaItem.mediaMetadata.artworkUri?.toString(),
                "url" to mediaItem.localConfiguration?.uri?.toString()
            )
        )
        activity?.runOnUiThread {
            eventSink?.success(event)
        }
    }

    private fun addToPlaylist(mediaItems: List<Map<String, Any>>) {
        val items = mediaItems.mapNotNull { item ->
            try {
                val url = item["url"] as? String
                if (url == null) {
                    Log.e("MediaPlayerPlugin", "Invalid URL in playlist item")
                    return@mapNotNull null
                }
                
                MediaItem.Builder()
                    .setMediaId(item["id"] as? String ?: "")
                    .setUri(url)
                    .setMediaMetadata(
                        MediaMetadata.Builder()
                            .setTitle(item["title"] as? String)
                            .setArtist(item["artist"] as? String)
                            .setDisplayTitle(item["album"] as? String)
                            .apply {
                                (item["artworkUrl"] as? String)?.let { artworkUrl ->
                                    try {
                                        setArtworkUri(android.net.Uri.parse(artworkUrl))
                                    } catch (e: Exception) {
                                        Log.e("MediaPlayerPlugin", "Failed to parse artwork URL: $artworkUrl", e)
                                    }
                                }
                            }
                            .build()
                    )
                    .build()
            } catch (e: Exception) {
                Log.e("MediaPlayerPlugin", "Failed to create MediaItem", e)
                null
            }
        }
        
        if (items.isNotEmpty()) {
            player?.addMediaItems(items)
            notifyPlaylistChanged()
        }
    }

    private fun skipToIndex(index: Int) {
        player?.seekToDefaultPosition(index)
    }

    private fun clearPlaylist() {
        player?.clearMediaItems()
        notifyPlaylistChanged()
    }

    private fun getPlaylistSize(): Int {
        return player?.mediaItemCount ?: 0
    }

    private fun getCurrentIndex(): Int {
        return player?.currentMediaItemIndex ?: 0
    }

    private fun notifyPlaylistChanged() {
        val currentItems = mutableListOf<Map<String, Any?>>()
        player?.let { exoPlayer ->
            for (i in 0 until exoPlayer.mediaItemCount) {
                exoPlayer.getMediaItemAt(i)?.let { mediaItem ->
                    currentItems.add(mapOf(
                        "id" to mediaItem.mediaId,
                        "title" to mediaItem.mediaMetadata.title?.toString(),
                        "artist" to mediaItem.mediaMetadata.artist?.toString(),
                        "album" to mediaItem.mediaMetadata.displayTitle?.toString(),
                        "artworkUrl" to mediaItem.mediaMetadata.artworkUri?.toString(),
                        "url" to mediaItem.localConfiguration?.uri?.toString()
                    ))
                }
            }
        }
        
        val event = mapOf(
            "type" to "playlistChanged",
            "data" to currentItems
        )
        activity?.runOnUiThread {
            eventSink?.success(event)
        }
    }

    private fun startPlaybackService() {
        if (!isServiceBound) {
            val intent = Intent(context, PlaybackService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.bindService(
                    intent,
                    serviceConnection,
                    Context.BIND_AUTO_CREATE or Context.BIND_IMPORTANT
                )
            } else {
                context.bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
            }
        }
    }

    private fun setupNotification(mediaItem: MediaItem) {
        startPlaybackService()
        
        // 创建返回应用的 Intent
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else {
            PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT
            )
        }

        mediaSession?.let { session ->
            playbackService?.setupNotification(
                session,
                mediaItem.mediaMetadata.title?.toString() ?: "Unknown",
                mediaItem.mediaMetadata.artist?.toString(),
                mediaItem.mediaMetadata.artworkUri?.toString(),
                pendingIntent
            )
        }
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "initialize" -> {
                if (player == null) {
                    initializePlayer()
                }
                result.success(null)
            }
            "setPlaylist" -> {
                try {
                    val playlist = call.argument<List<Map<String, Any>>>("playlist")
                    if (playlist != null) {
                        val mediaItems = playlist.mapNotNull { item ->
                            try {
                                val url = item["url"] as? String
                                if (url == null) {
                                    Log.e("MediaPlayerPlugin", "Invalid URL in playlist item")
                                    return@mapNotNull null
                                }
                                
                                MediaItem.Builder()
                                    .setMediaId(item["id"] as? String ?: "")
                                    .setUri(url)
                                    .setMediaMetadata(
                                        MediaMetadata.Builder()
                                            .setTitle(item["title"] as? String)
                                            .setArtist(item["artist"] as? String)
                                            .setDisplayTitle(item["album"] as? String)
                                            .apply {
                                                (item["artworkUrl"] as? String)?.let { artworkUrl ->
                                                    try {
                                                        setArtworkUri(android.net.Uri.parse(artworkUrl))
                                                    } catch (e: Exception) {
                                                        Log.e("MediaPlayerPlugin", "Failed to parse artwork URL: $artworkUrl", e)
                                                    }
                                                }
                                            }
                                            .build()
                                    )
                                    .build()
                            } catch (e: Exception) {
                                Log.e("MediaPlayerPlugin", "Failed to create MediaItem", e)
                                null
                            }
                        }
                        
                        if (mediaItems.isEmpty()) {
                            result.error("PLAYLIST_ERROR", "No valid media items in playlist", null)
                            return
                        }
                        
                        player?.setMediaItems(mediaItems)
                        player?.prepare()
                        notifyPlaylistChanged()
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Playlist is required", null)
                    }
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error setting playlist", e)
                    result.error("PLAYLIST_ERROR", e.message, null)
                }
            }
            "play" -> {
                player?.let { exoPlayer ->
                    exoPlayer.play()
                    exoPlayer.currentMediaItem?.let { setupNotification(it) }
                }
                result.success(null)
            }
            "pause" -> {
                player?.pause()
                result.success(null)
            }
            "stop" -> {
                player?.stop()
                result.success(null)
            }
            "seekTo" -> {
                val position = call.argument<Number>("position")?.toLong() ?: 0
                player?.seekTo(position)
                result.success(null)
            }
            "showVideoView" -> {
                videoViewFactory?.setVideoEnabled(true)
                result.success(null)
            }
            "hideVideoView" -> {
                videoViewFactory?.setVideoEnabled(false)
                result.success(null)
            }
            "addToPlaylist" -> {
                try {
                    val mediaItems = call.argument<List<Map<String, Any>>>("mediaItems")
                    if (mediaItems != null) {
                        addToPlaylist(mediaItems)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Media items cannot be null", null)
                    }
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error adding to playlist", e)
                    result.error("PLAYLIST_ERROR", e.message, null)
                }
            }
            "skipToIndex" -> {
                try {
                    val index = call.argument<Int>("index")
                    if (index != null) {
                        skipToIndex(index)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Index cannot be null", null)
                    }
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error skipping to index", e)
                    result.error("PLAYLIST_ERROR", e.message, null)
                }
            }
            "clearPlaylist" -> {
                try {
                    clearPlaylist()
                    result.success(null)
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error clearing playlist", e)
                    result.error("PLAYLIST_ERROR", e.message, null)
                }
            }
            "getPlaylistSize" -> {
                try {
                    result.success(getPlaylistSize())
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error getting playlist size", e)
                    result.error("PLAYLIST_ERROR", e.message, null)
                }
            }
            "getCurrentIndex" -> {
                try {
                    result.success(getCurrentIndex())
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error getting current index", e)
                    result.error("PLAYLIST_ERROR", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        
        if (isServiceBound) {
            try {
                context.unbindService(serviceConnection)
            } catch (e: Exception) {
                Log.e("MediaPlayerPlugin", "Error unbinding service", e)
            }
            isServiceBound = false
        }
        
        mediaSession?.release()
        player?.release()
        player = null
        mediaSession = null
        videoViewFactory = null
        serviceJob.cancel()
        flutterEngine = null
    }
}
