import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'media_player_method_channel.dart';

/// 媒体项数据模型
class MediaItem {
  final String id;
  final String title;
  final String? artist;
  final String? album;
  final Duration? duration;
  final String? artworkUrl;
  final String url;

  MediaItem({
    required this.id,
    required this.title,
    required this.url,
    this.artist,
    this.album,
    this.duration,
    this.artworkUrl,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'duration': duration?.inMilliseconds,
        'artworkUrl': artworkUrl,
        'url': url,
      };

  factory MediaItem.fromMap(Map<String, dynamic> map) => MediaItem(
        id: map['id'],
        title: map['title'],
        url: map['url'],
        artist: map['artist'],
        album: map['album'],
        duration: map['duration'] != null ? Duration(milliseconds: map['duration']) : null,
        artworkUrl: map['artworkUrl'],
      );
}

/// 播放状态枚举
enum PlaybackState { none, loading, ready, playing, paused, completed, error }

/// 平台接口抽象类
abstract class MediaPlayerPlatform extends PlatformInterface {
  MediaPlayerPlatform() : super(token: _token);

  static final Object _token = Object();
  static MediaPlayerPlatform _instance = MethodChannelMediaPlayer();

  static MediaPlayerPlatform get instance => _instance;

  static set instance(MediaPlayerPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// 初始化播放器
  Future<void> initialize() {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  /// 设置播放列表
  Future<void> setPlaylist(List<MediaItem> playlist) {
    throw UnimplementedError('setPlaylist() has not been implemented.');
  }

  /// 播放
  Future<void> play() {
    throw UnimplementedError('play() has not been implemented.');
  }

  /// 暂停
  Future<void> pause() {
    throw UnimplementedError('pause() has not been implemented.');
  }

  /// 停止
  Future<void> stop() {
    throw UnimplementedError('stop() has not been implemented.');
  }

  /// 跳转到指定位置
  Future<void> seekTo(Duration position) {
    throw UnimplementedError('seekTo() has not been implemented.');
  }

  /// 下一曲
  Future<void> skipToNext() {
    throw UnimplementedError('skipToNext() has not been implemented.');
  }

  /// 上一曲
  Future<void> skipToPrevious() {
    throw UnimplementedError('skipToPrevious() has not been implemented.');
  }

  /// 设置音量
  Future<void> setVolume(double volume) {
    throw UnimplementedError('setVolume() has not been implemented.');
  }

  /// 获取当前播放状态
  Future<PlaybackState> getPlaybackState() {
    throw UnimplementedError('getPlaybackState() has not been implemented.');
  }

  /// 获取当前播放位置
  Future<Duration> getCurrentPosition() {
    throw UnimplementedError('getCurrentPosition() has not been implemented.');
  }

  /// 获取当前播放项
  Future<MediaItem?> getCurrentMediaItem() {
    throw UnimplementedError('getCurrentMediaItem() has not been implemented.');
  }
}
