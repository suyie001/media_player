package com.example.media_player

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class MediaPlayerPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private lateinit var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding
    
    private val serviceJob = SupervisorJob()
    private val serviceScope = CoroutineScope(Dispatchers.Main + serviceJob)
    
    private var controllerFuture: ListenableFuture<MediaController>? = null
    private var controller: MediaController? = null
    private var videoViewFactory: VideoPlayerViewFactory? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        flutterPluginBinding = binding
        context = binding.applicationContext
        
        methodChannel = MethodChannel(binding.binaryMessenger, "media_player")
        methodChannel.setMethodCallHandler(this)
        
        eventChannel = EventChannel(binding.binaryMessenger, "media_player_events")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
        
        initializeController()
    }

    private fun initializeController() {
        android.util.Log.d("MediaPlayerPlugin", "Initializing controller")
        val sessionToken = SessionToken(
            context,
            ComponentName(context, MediaPlayerService::class.java)
        )
        
        controllerFuture = MediaController.Builder(context, sessionToken).buildAsync()
        controllerFuture?.addListener({
            android.util.Log.d("MediaPlayerPlugin", "Controller future completed")
            controller = controllerFuture?.get()
            controller?.let {
                android.util.Log.d("MediaPlayerPlugin", "Controller initialized successfully")
                it.addListener(playerListener)
                
                // 创建视频视图工厂
                videoViewFactory = VideoPlayerViewFactory(context, it)
                // 注册视频视图工厂
                flutterPluginBinding.platformViewRegistry.registerViewFactory(
                    "media_player_video_view",
                    videoViewFactory!!
                )
                android.util.Log.d("MediaPlayerPlugin", "Video view factory registered")
            } ?: android.util.Log.e("MediaPlayerPlugin", "Failed to get controller")
        }, MoreExecutors.directExecutor())
    }

    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            val state = when (playbackState) {
                Player.STATE_IDLE -> "none"
                Player.STATE_BUFFERING -> "loading"
                Player.STATE_READY -> "ready"
                Player.STATE_ENDED -> "completed"
                else -> "unknown"
            }
            
            eventSink?.success(mapOf(
                "type" to "playbackStateChanged",
                "data" to state
            ))
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            mediaItem?.let {
                eventSink?.success(mapOf(
                    "type" to "mediaItemChanged",
                    "data" to mediaItemToMap(it)
                ))
            }
        }
        
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            eventSink?.success(mapOf(
                "type" to "playbackStateChanged",
                "data" to if (isPlaying) "playing" else "paused"
            ))
        }
        
        override fun onPlayerError(error: androidx.media3.common.PlaybackException) {
            eventSink?.success(mapOf(
                "type" to "error",
                "data" to (error.message ?: "Unknown error")
            ))
        }
        
        override fun onIsLoadingChanged(isLoading: Boolean) {
            eventSink?.success(mapOf(
                "type" to "bufferingChanged",
                "data" to isLoading
            ))
            
            // 如果不在缓冲状态，发送缓冲进度
            if (!isLoading) {
                notifyBufferProgress()
            }
        }
        
        override fun onPositionDiscontinuity(
            oldPosition: Player.PositionInfo,
            newPosition: Player.PositionInfo,
            reason: Int
        ) {
            eventSink?.success(mapOf(
                "type" to "positionChanged",
                "data" to newPosition.positionMs
            ))
        }
    }
    
    private fun notifyBufferProgress() {
        controller?.let { player ->
            val duration = player.duration
            if (duration > 0) {
                val bufferedPosition = player.bufferedPosition
                val progress = (bufferedPosition.toFloat() / duration.toFloat()).coerceIn(0f, 1f)
                eventSink?.success(mapOf(
                    "type" to "bufferChanged",
                    "data" to progress
                ))
            }
        }
    }
    
    override fun onMethodCall(call: MethodCall, result: Result) {
        try {
            when (call.method) {
                "initialize" -> {
                    val intent = Intent(context, MediaPlayerService::class.java)
                    context.startService(intent)
                    result.success(null)
                }
                "setPlaylist" -> {
                    val playlist = call.argument<List<Map<String, Any>>>("playlist")
                    playlist?.let {
                        android.util.Log.d("MediaPlayerPlugin", "Setting playlist with ${it.size} items")
                        val mediaItems = it.map { item -> 
                            android.util.Log.d("MediaPlayerPlugin", "Creating MediaItem: ${item["url"]}")
                            createMediaItem(item) 
                        }
                        controller?.let { ctrl ->
                            android.util.Log.d("MediaPlayerPlugin", "Setting ${mediaItems.size} items to controller")
                            ctrl.setMediaItems(mediaItems)
                            ctrl.prepare()  // 添加这行确保播放器准备好播放
                            android.util.Log.d("MediaPlayerPlugin", "Media items set successfully")
                        } ?: android.util.Log.e("MediaPlayerPlugin", "Controller is null")
                        result.success(null)
                    } ?: result.error("INVALID_ARGUMENT", "Playlist is required", null)
                }
                "play" -> {
                    controller?.play()
                    result.success(null)
                }
                "pause" -> {
                    controller?.pause()
                    result.success(null)
                }
                "stop" -> {
                    controller?.stop()
                    result.success(null)
                }
                "seekTo" -> {
                    val position = call.argument<Int>("position")
                    position?.let {
                        controller?.seekTo(it.toLong())
                        result.success(null)
                    } ?: result.error("INVALID_ARGUMENT", "Position is required", null)
                }
                "skipToNext" -> {
                    controller?.seekToNextMediaItem()
                    result.success(null)
                }
                "skipToPrevious" -> {
                    controller?.seekToPreviousMediaItem()
                    result.success(null)
                }
                "setVolume" -> {
                    val volume = call.argument<Double>("volume")
                    volume?.let {
                        controller?.volume = it.toFloat()
                        result.success(null)
                    } ?: result.error("INVALID_ARGUMENT", "Volume is required", null)
                }
                "getPlaybackState" -> {
                    val state = when (controller?.playbackState) {
                        Player.STATE_IDLE -> "none"
                        Player.STATE_BUFFERING -> "loading"
                        Player.STATE_READY -> "ready"
                        Player.STATE_ENDED -> "completed"
                        else -> "none"
                    }
                    result.success(state)
                }
                "getCurrentPosition" -> {
                    result.success(controller?.currentPosition?.toInt() ?: 0)
                }
                "getCurrentMediaItem" -> {
                    val mediaItem = controller?.currentMediaItem
                    result.success(mediaItem?.let { mediaItemToMap(it) })
                }
                "add" -> {
                    val mediaItem = call.argument<Map<String, Any>>("mediaItem")
                    mediaItem?.let {
                        controller?.addMediaItem(createMediaItem(it))
                        result.success(null)
                    } ?: result.error("INVALID_ARGUMENT", "MediaItem is required", null)
                }
                "removeAt" -> {
                    val index = call.argument<Int>("index")
                    index?.let {
                        controller?.removeMediaItem(it)
                        result.success(null)
                    } ?: result.error("INVALID_ARGUMENT", "Index is required", null)
                }
                "insertAt" -> {
                    val index = call.argument<Int>("index")
                    val mediaItem = call.argument<Map<String, Any>>("mediaItem")
                    if (index != null && mediaItem != null) {
                        controller?.addMediaItem(index, createMediaItem(mediaItem))
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Index and mediaItem are required", null)
                    }
                }
                "move" -> {
                    val from = call.argument<Int>("from")
                    val to = call.argument<Int>("to")
                    if (from != null && to != null) {
                        controller?.moveMediaItem(from, to)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "From and to indices are required", null)
                    }
                }
                "jumpTo" -> {
                    val index = call.argument<Int>("index")
                    index?.let {
                        controller?.seekToDefaultPosition(it)
                        result.success(null)
                    } ?: result.error("INVALID_ARGUMENT", "Index is required", null)
                }
                "setPlayMode" -> {
                    val mode = call.argument<String>("mode")
                    mode?.let {
                        val playMode = when (it) {
                            "all" -> MediaPlayerService.PlayMode.ALL
                            "list" -> MediaPlayerService.PlayMode.LIST
                            "one" -> MediaPlayerService.PlayMode.ONE
                            "shuffle" -> MediaPlayerService.PlayMode.SHUFFLE
                            else -> MediaPlayerService.PlayMode.LIST
                        }
                        (controller as? MediaController)?.let { controller ->
                            when (playMode) {
                                MediaPlayerService.PlayMode.ALL -> {
                                    controller.repeatMode = Player.REPEAT_MODE_ALL
                                    controller.shuffleModeEnabled = false
                                }
                                MediaPlayerService.PlayMode.LIST -> {
                                    controller.repeatMode = Player.REPEAT_MODE_OFF
                                    controller.shuffleModeEnabled = false
                                }
                                MediaPlayerService.PlayMode.ONE -> {
                                    controller.repeatMode = Player.REPEAT_MODE_ONE
                                    controller.shuffleModeEnabled = false
                                }
                                MediaPlayerService.PlayMode.SHUFFLE -> {
                                    controller.repeatMode = Player.REPEAT_MODE_ALL
                                    controller.shuffleModeEnabled = true
                                }
                            }
                        }
                        result.success(null)
                    } ?: result.error("INVALID_ARGUMENT", "Mode is required", null)
                }
                "getPlayMode" -> {
                    val mode = when {
                        controller?.shuffleModeEnabled == true -> "shuffle"
                        controller?.repeatMode == Player.REPEAT_MODE_ONE -> "one"
                        controller?.repeatMode == Player.REPEAT_MODE_ALL -> "all"
                        else -> "list"
                    }
                    result.success(mode)
                }
                "showVideoView" -> {
                    if (videoViewFactory == null && controller != null) {
                        videoViewFactory = VideoPlayerViewFactory(context, controller!!)
                        flutterPluginBinding.platformViewRegistry.registerViewFactory(
                            "media_player_video_view",
                            videoViewFactory!!
                        )
                    }
                    result.success(null)
                }
                "hideVideoView" -> {
                    videoViewFactory = null
                    result.success(null)
                }
                "updateCurrentUrl" -> {
                    val url = call.argument<String>("url")
                    url?.let {
                        val mediaItem = MediaItem.fromUri(it)
                        controller?.setMediaItem(mediaItem)
                        result.success(null)
                    } ?: result.error("INVALID_ARGUMENT", "URL is required", null)
                }
                "startPictureInPicture" -> {
                    // PiP 功能将在后续实现
                    result.success(null)
                }
                "stopPictureInPicture" -> {
                    // PiP 功能将在后续实现
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error(
                "PLATFORM_ERROR",
                e.message ?: "An unknown error occurred",
                e.stackTraceToString()
            )
        }
    }

    private fun createMediaItem(map: Map<String, Any>): MediaItem {
        val metadata = MediaMetadata.Builder()
            .setTitle(map["title"] as? String)
            .setArtist(map["artist"] as? String)
            .setDisplayTitle(map["album"] as? String)
            .setArtworkUri((map["artworkUrl"] as? String)?.let { android.net.Uri.parse(it) })
            .build()

        return MediaItem.Builder()
            .setMediaId(map["id"] as String)
            .setMediaMetadata(metadata)
            .setUri(map["url"] as String)
            .build()
    }

    private fun mediaItemToMap(mediaItem: MediaItem): Map<String, Any?> {
        return mapOf(
            "id" to mediaItem.mediaId,
            "title" to mediaItem.mediaMetadata.title,
            "artist" to mediaItem.mediaMetadata.artist,
            "album" to mediaItem.mediaMetadata.displayTitle,
            "artworkUrl" to mediaItem.mediaMetadata.artworkUri?.toString(),
            "url" to mediaItem.localConfiguration?.uri?.toString()
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        controller?.release()
        controllerFuture?.cancel(true)
        serviceJob.cancel()
        videoViewFactory = null
    }

    private fun handleError(error: Exception, result: Result) {
        when (error) {
            is IllegalStateException -> result.error(
                "ILLEGAL_STATE",
                error.message ?: "Player is in an invalid state",
                error.stackTraceToString()
            )
            is IllegalArgumentException -> result.error(
                "INVALID_ARGUMENT",
                error.message ?: "Invalid argument provided",
                error.stackTraceToString()
            )
            else -> result.error(
                "PLATFORM_ERROR",
                error.message ?: "An unknown error occurred",
                error.stackTraceToString()
            )
        }
    }
}
