package com.example.media_player

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
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
    
    private val serviceJob = SupervisorJob()
    private val serviceScope = CoroutineScope(Dispatchers.Main + serviceJob)
    
    private var controllerFuture: ListenableFuture<MediaController>? = null
    private var controller: MediaController? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
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
        val sessionToken = SessionToken(
            context,
            ComponentName(context, MediaPlayerService::class.java)
        )
        
        controllerFuture = MediaController.Builder(context, sessionToken).buildAsync()
        controllerFuture?.addListener({
            controller = controllerFuture?.get()
            controller?.addListener(playerListener)
        }, MoreExecutors.directExecutor())
    }

    private val playerListener = object : androidx.media3.common.Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            val state = when (playbackState) {
                androidx.media3.common.Player.STATE_IDLE -> "none"
                androidx.media3.common.Player.STATE_BUFFERING -> "loading"
                androidx.media3.common.Player.STATE_READY -> "ready"
                androidx.media3.common.Player.STATE_ENDED -> "completed"
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
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> {
                val intent = Intent(context, MediaPlayerService::class.java)
                context.startService(intent)
                result.success(null)
            }
            "setPlaylist" -> {
                val playlist = call.argument<List<Map<String, Any>>>("playlist")
                playlist?.let {
                    val mediaItems = it.map { item -> createMediaItem(item) }
                    controller?.setMediaItems(mediaItems)
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
                controller?.seekToNext()
                result.success(null)
            }
            "skipToPrevious" -> {
                controller?.seekToPrevious()
                result.success(null)
            }
            "setVolume" -> {
                val volume = call.argument<Double>("volume")
                volume?.let {
                    controller?.volume = it.toFloat()
                    result.success(null)
                } ?: result.error("INVALID_ARGUMENT", "Volume is required", null)
            }
            else -> result.notImplemented()
        }
    }

    private fun createMediaItem(map: Map<String, Any>): MediaItem {
        val metadata = MediaMetadata.Builder()
            .setTitle(map["title"] as? String)
            .setArtist(map["artist"] as? String)
            .setAlbum(map["album"] as? String)
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
            "album" to mediaItem.mediaMetadata.album,
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
    }
}
