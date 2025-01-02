package com.example.media_player

import android.app.Activity
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.BroadcastReceiver
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
import android.app.PictureInPictureParams

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
    private val playHistory = mutableListOf<Int>()
    private var currentPlayMode = PlayMode.LIST
    private var notificationManager: NotificationManager? = null
    private var screenReceiver: BroadcastReceiver? = null
    private var isLoggingEnabled = false

    // 播放模式枚举
    enum class PlayMode {
        ALL,    // 列表循环
        LIST,   // 列表播放一次
        ONE,    // 单曲循环
        SHUFFLE // 随机播放
    }

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
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        // 确保在主线程中初始化和注册视频视图工厂
        Handler(Looper.getMainLooper()).post {
            if (player == null) {
                initializePlayer()
            }
            // 创建并注册视频视图工厂
            videoViewFactory = VideoPlayerViewFactory(context, player!!)
            flutterEngine?.platformViewsController?.registry
                ?.registerViewFactory("media_player_video_view", videoViewFactory!!)
            
            // 注册屏幕锁定广播接收器
            registerScreenReceiver()
        }
    }

    private fun registerScreenReceiver() {
        if (screenReceiver == null) {
            screenReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    when (intent?.action) {
                        Intent.ACTION_SCREEN_OFF -> {
                            log("MediaPlayerPlugin", "Screen turned off")
                            Handler(Looper.getMainLooper()).postDelayed({
                                player?.currentMediaItem?.let { mediaItem ->
                                    setupNotification(mediaItem)
                                }
                            }, 1000)
                        }
                        Intent.ACTION_USER_PRESENT -> {
                            log("MediaPlayerPlugin", "Screen unlocked")
                            player?.currentMediaItem?.let { mediaItem ->
                                setupNotification(mediaItem)
                            }
                        }
                    }
                }
            }

            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_USER_PRESENT)
            }
            
            context.registerReceiver(screenReceiver, filter)
        }
    }

    private fun unregisterScreenReceiver() {
        screenReceiver?.let {
            try {
                context.unregisterReceiver(it)
                screenReceiver = null
            } catch (e: Exception) {
                Log.e("MediaPlayerPlugin", "Error unregistering screen receiver", e)
            }
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
                .apply {
                    addListener(playerListener)
                    addPeriodicTimeUpdateListener()
                }

            mediaSession = player?.let { 
                MediaSession.Builder(context, it)
                    .setCallback(mediaSessionCallback)
                    .setId("MediaPlayerService")
                    .build()
            }

            notificationManager = NotificationManager(context)

            log("MediaPlayerPlugin", "Player initialized successfully")
        } catch (e: Exception) {
            log("MediaPlayerPlugin", "Failed to initialize player: ${e.message}", true)
            throw e
        }
    }

    private fun Player.addPeriodicTimeUpdateListener() {
        val handler = Handler(Looper.getMainLooper())
        val updateIntervalMs = 1000L // 每秒更新一次
        
        val updateRunnable = object : Runnable {
            override fun run() {
                if (isPlaying) {
                    notifyPositionChanged(currentPosition)
                }
                handler.postDelayed(this, updateIntervalMs)
            }
        }
        
        addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (isPlaying) {
                    handler.post(updateRunnable)
                } else {
                    handler.removeCallbacks(updateRunnable)
                    // 暂停时也发送一次位置更新
                    notifyPositionChanged(currentPosition)
                }
            }
            
            override fun onPlaybackStateChanged(playbackState: Int) {
                when (playbackState) {
                    Player.STATE_ENDED -> {
                        handler.removeCallbacks(updateRunnable)
                        notifyPositionChanged(duration)
                    }
                    Player.STATE_IDLE -> {
                        handler.removeCallbacks(updateRunnable)
                        notifyPositionChanged(0)
                    }
                }
            }
        })
    }

    private var eventSink: EventChannel.EventSink? = null

    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            val state = when (playbackState) {
                Player.STATE_IDLE -> "none"
                Player.STATE_BUFFERING -> "loading"
                Player.STATE_READY -> {
                    // 播放器准备好时发送时长
                    player?.duration?.let { duration ->
                        notifyDurationChanged(duration)
                    }
                    "ready"
                }
                Player.STATE_ENDED -> {
                    notifyCompleted()
                    "completed"
                }
                else -> "unknown"
            }
            notifyPlaybackStateChanged(state)
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            mediaItem?.let { 
                notifyMediaItemChanged(it)
                setupNotification(it)
                notifyPlaylistChanged()
                // 更新时长
                player?.duration?.let { duration ->
                    notifyDurationChanged(duration)
                }
            }
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            if (isPlaying) {
                startPeriodicPositionUpdates()
            } else {
                stopPeriodicPositionUpdates()
                // 暂停时发送一次最新位置
                player?.currentPosition?.let { position ->
                    notifyPositionChanged(position)
                }
            }
        }

        override fun onTimelineChanged(timeline: Timeline, reason: Int) {
            notifyPlaylistChanged()
            // 时间线变化时检查时长
            player?.duration?.let { duration ->
                if (duration > 0) {
                    notifyDurationChanged(duration)
                }
            }
        }

        override fun onRepeatModeChanged(repeatMode: Int) {
            val mode = when (repeatMode) {
                Player.REPEAT_MODE_ONE -> "single"
                Player.REPEAT_MODE_ALL -> "all"
                else -> "off"
            }
            notifyPlaybackModeChanged(mode)
        }

        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
            val state = if (playWhenReady) "playing" else "paused"
            notifyPlaybackStateChanged(state)
        }

        override fun onPlayerError(error: PlaybackException) {
            notifyError(error.message ?: "Unknown error")
        }

        override fun onPositionDiscontinuity(
            oldPosition: Player.PositionInfo,
            newPosition: Player.PositionInfo,
            reason: Int
        ) {
            // 处理跳转等导致的位置突变
            notifyPositionChanged(newPosition.positionMs)
        }

        override fun onPlaybackParametersChanged(playbackParameters: PlaybackParameters) {
            // 添加播放速度变化的通知，
            notifyPlaybackSpeedChanged(playbackParameters.speed)
            // notifyPlaybackStateChanged("playing")
            // player?.currentMediaItem?.let { setupNotification(it) }

        }

        override fun onLoadingChanged(isLoading: Boolean) {
            notifyBufferingChanged(isLoading)
        }

        override fun onAvailableCommandsChanged(availableCommands: Player.Commands) {
            // 可以在这里添加可用命令变化的通知，如果需要的话
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

    private fun notifyPositionChanged(position: Long) {
        val event = mapOf(
            "type" to "positionChanged",
            "data" to position
        )
        activity?.runOnUiThread {
            eventSink?.success(event)
        }
    }

    private fun notifyDurationChanged(duration: Long) {
        val event = mapOf(
            "type" to "durationChanged",
            "data" to duration
        )
        activity?.runOnUiThread {
            eventSink?.success(event)
        }
    }

    private fun notifyBufferChanged(progress: Double) {
        val event = mapOf(
            "type" to "bufferChanged",
            "data" to progress
        )
        activity?.runOnUiThread {
            eventSink?.success(event)
        }
    }

    private fun notifyBufferingChanged(isBuffering: Boolean) {
        val event = mapOf(
            "type" to "bufferingChanged",
            "data" to isBuffering
        )
        activity?.runOnUiThread {
            eventSink?.success(event)
        }
    }

    private fun notifyPlaybackModeChanged(mode: String) {
        val event = mapOf(
            "type" to "playModeChanged",
            "data" to mode
        )
        activity?.runOnUiThread {
            eventSink?.success(event)
        }
    }

    private fun notifyError(error: String) {
        val event = mapOf(
            "type" to "errorOccurred",
            "data" to error
        )
        activity?.runOnUiThread {
            eventSink?.success(event)
        }
    }

    private fun notifyCompleted() {
        val event = mapOf(
            "type" to "completed",
            "data" to true
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

        player?.let { player ->
            mediaSession?.let { session ->
                notificationManager?.createNotification(
                    player,
                    session,
                    pendingIntent
                )
            }
        }
    }

    private fun handleNextItem() {
        player?.let { exoPlayer ->
            when (currentPlayMode) {
                PlayMode.SHUFFLE -> {
                    // 在随机模式下，记录当前项目到历史
                    val currentIndex = exoPlayer.currentMediaItemIndex
                    playHistory.add(currentIndex)
                    
                    // 生成一个随机的下一个索引，排除当前正在播放的索引
                    val mediaItemCount = exoPlayer.mediaItemCount
                    if (mediaItemCount > 1) {
                        val availableIndices = (0 until mediaItemCount).filter { it != currentIndex }
                        val nextIndex = availableIndices.random()
                        Log.d("MediaPlayerPlugin", "Shuffle next: current=$currentIndex, next=$nextIndex")
                        exoPlayer.seekToDefaultPosition(nextIndex)
                    }
                }
                else -> {
                    if (exoPlayer.hasNextMediaItem()) {
                        exoPlayer.seekToNextMediaItem()
                    } else if (currentPlayMode == PlayMode.ALL) {
                        // 列表循环模式下，返回到第一首
                        exoPlayer.seekToDefaultPosition(0)
                    }
                }
            }
        }
    }

    private fun handlePreviousItem() {
        player?.let { exoPlayer ->
            when (currentPlayMode) {
                PlayMode.SHUFFLE -> {
                    // 在随机模式下，从历史记录中获取上一个项目
                    if (playHistory.isNotEmpty()) {
                        val previousIndex = playHistory.removeAt(playHistory.size - 1)
                        Log.d("MediaPlayerPlugin", "Shuffle previous: going back to $previousIndex")
                        exoPlayer.seekToDefaultPosition(previousIndex)
                    } else {
                        // 如果没有历史记录，随机选择一个不同的索引
                        val currentIndex = exoPlayer.currentMediaItemIndex
                        val mediaItemCount = exoPlayer.mediaItemCount
                        if (mediaItemCount > 1) {
                            val availableIndices = (0 until mediaItemCount).filter { it != currentIndex }
                            val randomIndex = availableIndices.random()
                            Log.d("MediaPlayerPlugin", "Shuffle previous (no history): current=$currentIndex, random=$randomIndex")
                            exoPlayer.seekToDefaultPosition(randomIndex)
                        }
                    }
                }
                else -> {
                    if (exoPlayer.hasPreviousMediaItem()) {
                        exoPlayer.seekToPreviousMediaItem()
                    } else if (currentPlayMode == PlayMode.ALL) {
                        // 列表循环模式下，跳转到最后一首
                        exoPlayer.seekToDefaultPosition(exoPlayer.mediaItemCount - 1)
                    }
                }
            }
        }
    }

    private fun log(tag: String, message: String, isError: Boolean = false) {
        if (isLoggingEnabled) {
            if (isError) {
                Log.e(tag, message)
            } else {
                Log.d(tag, message)
            }
            // 发送日志事件到 Flutter
            val event = mapOf(
                "type" to "log",
                "data" to mapOf(
                    "tag" to tag,
                    "message" to message,
                    "isError" to isError,
                    "timestamp" to System.currentTimeMillis()
                )
            )
            activity?.runOnUiThread {
                eventSink?.success(event)
            }
        }
    }

    private var periodicPositionUpdateJob: Runnable? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    
    private fun startPeriodicPositionUpdates() {
        stopPeriodicPositionUpdates() // 先停止现有的更新
        
        periodicPositionUpdateJob = object : Runnable {
            override fun run() {
                player?.let { player ->
                    if (player.isPlaying) {
                        notifyPositionChanged(player.currentPosition)
                        // 每500ms更新一次
                        mainHandler.postDelayed(this, 500)
                    }
                }
            }
        }.also {
            mainHandler.post(it)
        }
    }

    private fun stopPeriodicPositionUpdates() {
        periodicPositionUpdateJob?.let { mainHandler.removeCallbacks(it) }
        periodicPositionUpdateJob = null
    }

    private fun notifyPlaybackSpeedChanged(speed: Float) {
        val event = mapOf(
            "type" to "playbackSpeedChanged",
            "data" to speed
        )
        activity?.runOnUiThread {
            eventSink?.success(event)
        }
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "initialize" -> {
                try {
                    Handler(Looper.getMainLooper()).post {
                        try {
                            if (player == null) {
                                initializePlayer()
                            }
                            result.success(null)
                        } catch (e: Exception) {
                            Log.e("MediaPlayerPlugin", "Error initializing player", e)
                            result.error("INIT_ERROR", e.message, null)
                        }
                    }
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error posting to main thread", e)
                    result.error("INIT_ERROR", e.message, null)
                }
            }
            "setPlaylist" -> {
                try {
                    val playlist = call.argument<List<Map<String, Any>>>("playlist")
                    if (playlist != null) {
                        val mediaItems = playlist.mapNotNull { item ->
                            try {
                                val url = item["url"] as? String ?: return@mapNotNull null
                                
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
                        
                        // 在准备播放器后发送播放列表变化和时长
                        notifyPlaylistChanged()
                        player?.duration?.let { duration ->
                            if (duration > 0) {
                                notifyDurationChanged(duration)
                            }
                        }
                        
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
                    // 手动触发播放状态变化通知
                    notifyPlaybackStateChanged("playing")
                    val event = mapOf(
                        "type" to "isPlayingChanged",
                        "data" to true
                    )
                    activity?.runOnUiThread {
                        eventSink?.success(event)
                    }
                }
                result.success(null)
            }
            "pause" -> {
                player?.let { exoPlayer ->
                    exoPlayer.pause()
                    // 手动触发暂停状态变化通知
                    notifyPlaybackStateChanged("paused")
                    val event = mapOf(
                        "type" to "isPlayingChanged",
                        "data" to false
                    )
                    activity?.runOnUiThread {
                        eventSink?.success(event)
                    }
                }
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
            "setPlayMode" -> {
                try {
                    val mode = call.argument<String>("mode") ?: "all"
                    Log.d("MediaPlayerPlugin", "setPlayMode: $mode")
                    currentPlayMode = when (mode) {
                        "single" -> PlayMode.ONE
                        "all" -> PlayMode.ALL
                        "shuffle" -> PlayMode.SHUFFLE
                        else -> PlayMode.LIST
                    }
                    player?.repeatMode = when (currentPlayMode) {
                        PlayMode.ONE -> Player.REPEAT_MODE_ONE
                        PlayMode.ALL -> Player.REPEAT_MODE_ALL
                        PlayMode.SHUFFLE -> Player.REPEAT_MODE_ALL
                        else -> Player.REPEAT_MODE_OFF
                    }
                    // 切换到随机模式时清空历史记录
                    if (currentPlayMode == PlayMode.SHUFFLE) {
                        playHistory.clear()
                    }
                    notifyPlaybackModeChanged(mode)
                    result.success(null)
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error setting play mode", e)
                    result.error("PLAYER_ERROR", e.message, null)
                }
            }
            "jumpTo" -> {
                try {
                    val index = call.argument<Int>("index")
                    if (index != null) {
                        skipToIndex(index)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Index cannot be null", null)
                    }
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error jumping to index", e)
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
            "setLooping" -> {
                try {
                    val looping = call.argument<Boolean>("looping") ?: false
                    player?.repeatMode = if (looping) Player.REPEAT_MODE_ALL else Player.REPEAT_MODE_OFF
                    result.success(null)
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error setting looping", e)
                    result.error("PLAYER_ERROR", e.message, null)
                }
            }
            "setVolume" -> {
                try {
                    val volume = call.argument<Double>("volume") ?: 1.0
                    player?.volume = volume.toFloat()
                    result.success(null)
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error setting volume", e)
                    result.error("PLAYER_ERROR", e.message, null)
                }
            }
            "setSpeed" -> {
                try {
                    val speed = call.argument<Double>("speed") ?: 1.0
                    player?.setPlaybackSpeed(speed.toFloat())
                    result.success(null)
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error setting speed", e)
                    result.error("PLAYER_ERROR", e.message, null)
                }
            }
            "getPosition" -> {
                try {
                    val position = player?.currentPosition ?: 0
                    result.success(position)
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error getting position", e)
                    result.error("PLAYER_ERROR", e.message, null)
                }
            }
            "getDuration" -> {
                try {
                    val duration = player?.duration ?: 0
                    result.success(duration)
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error getting duration", e)
                    result.error("PLAYER_ERROR", e.message, null)
                }
            }
            "isPlaying" -> {
                try {
                    val isPlaying = player?.isPlaying ?: false
                    result.success(isPlaying)
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error checking playing state", e)
                    result.error("PLAYER_ERROR", e.message, null)
                }
            }
            "getBufferedPosition" -> {
                try {
                    val bufferedPosition = player?.bufferedPosition ?: 0
                    result.success(bufferedPosition)
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error getting buffered position", e)
                    result.error("PLAYER_ERROR", e.message, null)
                }
            }
            "setPlaybackMode" -> {
                try {
                    val mode = call.argument<String>("mode") ?: "all"
                    player?.repeatMode = when (mode) {
                        "single" -> Player.REPEAT_MODE_ONE
                        "all" -> Player.REPEAT_MODE_ALL
                        else -> Player.REPEAT_MODE_OFF
                    }
                    notifyPlaybackModeChanged(mode)
                    result.success(null)
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error setting playback mode", e)
                    result.error("PLAYER_ERROR", e.message, null)
                }
            }
            "getPlaybackMode" -> {
                try {
                    val mode = when (player?.repeatMode) {
                        Player.REPEAT_MODE_ONE -> "single"
                        Player.REPEAT_MODE_ALL -> "all"
                        else -> "off"
                    }
                    result.success(mode)
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error getting playback mode", e)
                    result.error("PLAYER_ERROR", e.message, null)
                }
            }
            "move" -> {
                try {
                    val from = call.argument<Int>("from") ?: 0
                    val to = call.argument<Int>("to") ?: 0
                    player?.moveMediaItem(from, to)
                    notifyPlaylistChanged()
                    result.success(null)
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error moving playlist item", e)
                    result.error("PLAYLIST_ERROR", e.message, null)
                }
            }
            "skipToPrevious" -> {
                try {
                    handlePreviousItem()
                    result.success(null)
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error skipping to previous", e)
                    result.error("PLAYER_ERROR", e.message, null)
                }
            }
            "skipToNext" -> {
                try {
                    handleNextItem()
                    result.success(null)
                } catch (e: Exception) {
                    Log.e("MediaPlayerPlugin", "Error skipping to next", e)
                    result.error("PLAYER_ERROR", e.message, null)
                }
            }
            "setLoggingEnabled" -> {
                try {
                    isLoggingEnabled = call.argument<Boolean>("enabled") ?: false
                    log("MediaPlayerPlugin", "Logging ${if (isLoggingEnabled) "enabled" else "disabled"}")
                    result.success(null)
                } catch (e: Exception) {
                    result.error("LOGGING_ERROR", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        
        notificationManager?.hideNotification()
        unregisterScreenReceiver()
        
        mediaSession?.release()
        player?.release()
        player = null
        mediaSession = null
        videoViewFactory = null
        serviceJob.cancel()
        flutterEngine = null
        stopPeriodicPositionUpdates()
    }
}
