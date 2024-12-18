import 'package:flutter/services.dart';
import 'media_player_platform_interface.dart';

/// 媒体播放器事件
class MediaPlayerEvent {
  final MediaPlayerEventType type;
  final dynamic data;

  MediaPlayerEvent(this.type, this.data);

  factory MediaPlayerEvent.fromMap(Map<String, dynamic> map) {
    final type = MediaPlayerEventType.values.firstWhere(
      (e) => e.toString().split('.').last == map['type'],
      orElse: () => MediaPlayerEventType.unknown,
    );
    return MediaPlayerEvent(type, map['data']);
  }
}

/// 事件类型枚举
enum MediaPlayerEventType {
  playbackStateChanged,
  mediaItemChanged,
  playlistChanged,
  positionChanged,
  errorOccurred,
  unknown,
}

/// 事件通道管理器
class MediaPlayerEventChannel {
  static const EventChannel _eventChannel = EventChannel('media_player_events');

  Stream<MediaPlayerEvent>? _eventStream;

  /// 获取事件流
  Stream<MediaPlayerEvent> get eventStream {
    _eventStream ??= _eventChannel.receiveBroadcastStream().map((event) {
      if (event is! Map) return MediaPlayerEvent(MediaPlayerEventType.unknown, null);
      return MediaPlayerEvent.fromMap(Map<String, dynamic>.from(event));
    });
    return _eventStream!;
  }

  /// 获取播放状态流
  Stream<PlaybackState> get playbackStateStream =>
      eventStream.where((event) => event.type == MediaPlayerEventType.playbackStateChanged).map((event) => PlaybackState.values.firstWhere(
            (e) => e.toString().split('.').last == event.data,
            orElse: () => PlaybackState.none,
          ));

  /// 获取当前媒体项流
  Stream<MediaItem?> get mediaItemStream => eventStream
      .where((event) => event.type == MediaPlayerEventType.mediaItemChanged)
      .map((event) => event.data != null ? MediaItem.fromMap(Map<String, dynamic>.from(event.data as Map)) : null);

  /// 获取播放列表变化流
  Stream<List<MediaItem>> get playlistStream => eventStream
      .where((event) => event.type == MediaPlayerEventType.playlistChanged)
      .map((event) => (event.data as List).map((item) => MediaItem.fromMap(Map<String, dynamic>.from(item as Map))).toList());

  /// 获取播放位置流
  Stream<Duration> get positionStream =>
      eventStream.where((event) => event.type == MediaPlayerEventType.positionChanged).map((event) => Duration(milliseconds: event.data));

  /// 获取错误流
  Stream<String> get errorStream => eventStream.where((event) => event.type == MediaPlayerEventType.errorOccurred).map((event) => event.data.toString());
}