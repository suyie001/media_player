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
  durationChanged,
  completed,
  bufferChanged,
  bufferingChanged,
  errorOccurred,
  playModeChanged,
  log,
  unknown,
  speedChanged,
}

/// 日志事件数据
class LogData {
  final String tag;
  final String message;
  final bool isError;
  final DateTime timestamp;

  LogData({
    required this.tag,
    required this.message,
    required this.isError,
    required this.timestamp,
  });

  factory LogData.fromMap(Map<String, dynamic> map) {
    return LogData(
      tag: map['tag'] as String,
      message: map['message'] as String,
      isError: map['isError'] as bool,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
    );
  }
}

/// 事件通道管理器
class MediaPlayerEventChannel {
  static const EventChannel _eventChannel = EventChannel('media_player_events');

  Stream<MediaPlayerEvent>? _eventStream;

  /// 获取事件流
  Stream<MediaPlayerEvent> get eventStream {
    _eventStream ??= _eventChannel.receiveBroadcastStream().map((event) {
      print('event: $event');
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

  /// 获取媒体时长流
  Stream<Duration> get durationStream =>
      eventStream.where((event) => event.type == MediaPlayerEventType.durationChanged).map((event) => Duration(milliseconds: event.data));

  /// 获取播放完成流
  Stream<bool> get completedStream => eventStream.where((event) => event.type == MediaPlayerEventType.completed).map((event) => event.data as bool);

  /// 获取缓冲进度流
  Stream<double> get bufferStream => eventStream.where((event) => event.type == MediaPlayerEventType.bufferChanged).map((event) => event.data as double);

  /// 获取缓冲状态流
  Stream<bool> get bufferingStream => eventStream.where((event) => event.type == MediaPlayerEventType.bufferingChanged).map((event) => event.data as bool);

  /// 获取错误流
  Stream<String> get errorStream => eventStream.where((event) => event.type == MediaPlayerEventType.errorOccurred).map((event) => event.data.toString());

  /// 获取播���模式变化流
  Stream<PlayMode> get playModeStream =>
      eventStream.where((event) => event.type == MediaPlayerEventType.playModeChanged).map((event) => PlayMode.values.firstWhere(
            (e) => e.toString().split('.').last == event.data,
            orElse: () => PlayMode.list,
          ));

  /// 获取播放速度变化流
  Stream<double> get speedStream => eventStream.where((event) => event.type == MediaPlayerEventType.speedChanged).map((event) => event.data as double);

  /// 获取日志流
  Stream<LogData> get logStream =>
      eventStream.where((event) => event.type == MediaPlayerEventType.log).map((event) => LogData.fromMap(Map<String, dynamic>.from(event.data as Map)));
}
