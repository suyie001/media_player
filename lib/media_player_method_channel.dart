import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'media_player_platform_interface.dart';

/// Method channel implementation of [MediaPlayerPlatform].
class MethodChannelMediaPlayer extends MediaPlayerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('media_player');

  @override
  Future<void> initialize() {
    return methodChannel.invokeMethod('initialize');
  }

  @override
  Future<void> setPlaylist(List<MediaItem> playlist) {
    return methodChannel.invokeMethod('setPlaylist', {
      'playlist': playlist.map((item) => item.toMap()).toList(),
    });
  }

  @override
  Future<void> play() {
    return methodChannel.invokeMethod('play');
  }

  @override
  Future<void> pause() {
    return methodChannel.invokeMethod('pause');
  }

  @override
  Future<void> stop() {
    return methodChannel.invokeMethod('stop');
  }

  @override
  Future<void> seekTo(Duration position) {
    return methodChannel.invokeMethod('seekTo', {
      'position': position.inMilliseconds,
    });
  }

  @override
  Future<void> skipToNext() {
    return methodChannel.invokeMethod('skipToNext');
  }

  @override
  Future<void> skipToPrevious() {
    return methodChannel.invokeMethod('skipToPrevious');
  }

  @override
  Future<void> setVolume(double volume) {
    return methodChannel.invokeMethod('setVolume', {
      'volume': volume,
    });
  }

  @override
  Future<PlaybackState> getPlaybackState() async {
    final state = await methodChannel.invokeMethod<String>('getPlaybackState');
    return PlaybackState.values.firstWhere(
      (e) => e.toString().split('.').last == state,
      orElse: () => PlaybackState.none,
    );
  }

  @override
  Future<Duration> getCurrentPosition() async {
    final position = await methodChannel.invokeMethod<int>('getCurrentPosition');
    return Duration(milliseconds: position ?? 0);
  }

  @override
  Future<MediaItem?> getCurrentMediaItem() async {
    final map = await methodChannel.invokeMethod<Map<dynamic, dynamic>>('getCurrentMediaItem');
    return map != null ? MediaItem.fromMap(Map<String, dynamic>.from(map)) : null;
  }
}
