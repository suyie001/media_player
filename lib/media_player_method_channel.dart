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

  Future<int> videoPlayerId(int id) async {
    return await methodChannel.invokeMethod('video_player_$id');
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

  @override
  Future<void> add(MediaItem mediaItem) {
    return methodChannel.invokeMethod('add', {
      'mediaItem': mediaItem.toMap(),
    });
  }

  @override
  Future<void> removeAt(int index) {
    return methodChannel.invokeMethod('removeAt', {
      'index': index,
    });
  }

  @override
  Future<void> insertAt(int index, MediaItem mediaItem) {
    return methodChannel.invokeMethod('insertAt', {
      'index': index,
      'mediaItem': mediaItem.toMap(),
    });
  }

  @override
  Future<void> move(int from, int to) {
    return methodChannel.invokeMethod('move', {
      'from': from,
      'to': to,
    });
  }

  @override
  Future<void> jumpTo(int index) {
    return methodChannel.invokeMethod('jumpTo', {
      'index': index,
    });
  }

  @override
  Future<void> setPlayMode(PlayMode mode) {
    return methodChannel.invokeMethod('setPlayMode', {
      'mode': mode.toString().split('.').last,
    });
  }

  @override
  Future<PlayMode> getPlayMode() async {
    final mode = await methodChannel.invokeMethod<String>('getPlayMode');
    return PlayMode.values.firstWhere(
      (e) => e.toString().split('.').last == mode,
      orElse: () => PlayMode.list,
    );
  }

  @override
  Future<void> showVideoView() async {
    await methodChannel.invokeMethod('showVideoView');
  }

  @override
  Future<void> hideVideoView() async {
    await methodChannel.invokeMethod('hideVideoView');
  }
}
