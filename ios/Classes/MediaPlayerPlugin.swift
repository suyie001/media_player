import Flutter
import UIKit

public class MediaPlayerPlugin: NSObject, FlutterPlugin {
    private let mediaPlayer = MediaPlayerHandler()
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "media_player", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "media_player_events", binaryMessenger: registrar.messenger())
        
        let instance = MediaPlayerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            result(nil)
            
        case "setPlaylist":
            guard let args = call.arguments as? [String: Any],
                  let playlist = args["playlist"] as? [[String: Any]] else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "Playlist is required",
                                  details: nil))
                return
            }
            mediaPlayer.setPlaylist(playlist)
            result(nil)
            
        case "setPlayMode":
            guard let args = call.arguments as? [String: Any],
                  let mode = args["mode"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "Play mode is required",
                                  details: nil))
                return
            }
            mediaPlayer.setPlayMode(mode)
            result(nil)
            
        case "getPlayMode":
            result(mediaPlayer.getPlayMode())
            
        case "add":
            guard let args = call.arguments as? [String: Any],
                  let mediaItem = args["mediaItem"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "MediaItem is required",
                                  details: nil))
                return
            }
            mediaPlayer.add(mediaItem)
            result(nil)
            
        case "removeAt":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "Index is required",
                                  details: nil))
                return
            }
            mediaPlayer.removeAt(index)
            result(nil)
            
        case "insertAt":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int,
                  let mediaItem = args["mediaItem"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "Index and mediaItem are required",
                                  details: nil))
                return
            }
            mediaPlayer.insertAt(index, mediaItem: mediaItem)
            result(nil)
            
        case "move":
            guard let args = call.arguments as? [String: Any],
                  let from = args["from"] as? Int,
                  let to = args["to"] as? Int else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "From and to indices are required",
                                  details: nil))
                return
            }
            mediaPlayer.move(from, to)
            result(nil)
            
        case "jumpTo":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "Index is required",
                                  details: nil))
                return
            }
            mediaPlayer.jumpTo(index)
            result(nil)
            
        case "play":
            mediaPlayer.play()
            result(nil)
            
        case "pause":
            mediaPlayer.pause()
            result(nil)
            
        case "stop":
            mediaPlayer.stop()
            result(nil)
            
        case "seekTo":
            guard let args = call.arguments as? [String: Any],
                  let position = args["position"] as? Int else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "Position is required",
                                  details: nil))
                return
            }
            mediaPlayer.seekTo(position: TimeInterval(position) / 1000.0)
            result(nil)
            
        case "skipToNext":
            mediaPlayer.skipToNext()
            result(nil)
            
        case "skipToPrevious":
            mediaPlayer.skipToPrevious()
            result(nil)
            
        case "setVolume":
            guard let args = call.arguments as? [String: Any],
                  let volume = args["volume"] as? Double else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                  message: "Volume is required",
                                  details: nil))
                return
            }
            mediaPlayer.setVolume(Float(volume))
            result(nil)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

// MARK: - FlutterStreamHandler

extension MediaPlayerPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        mediaPlayer.setEventSink(events)
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        mediaPlayer.setEventSink { _ in }
        return nil
    }
}
