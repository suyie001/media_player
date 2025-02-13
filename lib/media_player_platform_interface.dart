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

  /// 创建一个新的 MediaItem，可以选择性地����新某些字段
  MediaItem copyWith({
    String? id,
    String? title,
    String? url,
    String? artist,
    String? album,
    Duration? duration,
    String? artworkUrl,
  }) {
    return MediaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      artworkUrl: artworkUrl ?? this.artworkUrl,
    );
  }
}

/// 播放状态枚举
enum PlaybackState { none, loading, ready, playing, paused, completed, error }

/// 播放模式枚举
enum PlayMode {
  /// 列表循环（播完最后一首后从头开始）
  all,

  // /// 列表播放一次（播完最后一首后停止）
  // list,

  /// 单曲循环
  one,

  /// 随机播放
  shuffle
}

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

  /// 添加一个媒体项到播放列表
  Future<void> add(MediaItem mediaItem) {
    throw UnimplementedError('add() has not been implemented.');
  }

  /// 从播放列表中移除指定位置的媒体项
  Future<void> removeAt(int index) {
    throw UnimplementedError('removeAt() has not been implemented.');
  }

  /// 在指定位置插入一个媒体项
  Future<void> insertAt(int index, MediaItem mediaItem) {
    throw UnimplementedError('insertAt() has not been implemented.');
  }

  /// 移动播放列表中的媒体项
  Future<void> move(int from, int to) {
    throw UnimplementedError('move() has not been implemented.');
  }

  /// 更新指定位置的媒体项
  Future<void> updateAt(int index, MediaItem mediaItem) {
    throw UnimplementedError('updateAt() has not been implemented.');
  }

  /// 跳转到指定位置的媒体项
  Future<void> jumpTo(int index) {
    throw UnimplementedError('jumpTo() has not been implemented.');
  }

  /// 设置播放模式
  Future<void> setPlayMode(PlayMode mode) {
    throw UnimplementedError('setPlayMode() has not been implemented.');
  }

  /// 获取当前播放模式
  Future<PlayMode> getPlayMode() {
    throw UnimplementedError('getPlayMode() has not been implemented.');
  }

  /// 设置播放速度
  Future<void> setPlaybackSpeed(double speed) {
    throw UnimplementedError('setPlaybackSpeed() has not been implemented.');
  }

  /// 获取当前播放速度
  Future<double> speedStream() {
    throw UnimplementedError('getPlaybackSpeed() has not been implemented.');
  }

  /// 显示视频画面
  Future<void> showVideoView() {
    throw UnimplementedError('showVideoView() has not been implemented.');
  }

  /// 隐藏视频画面
  Future<void> hideVideoView() {
    throw UnimplementedError('hideVideoView() has not been implemented.');
  }

  /// 更新当前播放URL
  Future<void> updateCurrentUrl(String url) {
    throw UnimplementedError('updateCurrentUrl() has not been implemented.');
  }

  /// 是否支持画中画
  Future<bool> isPictureInPictureSupported() {
    throw UnimplementedError('supportsPictureInPicture() has not been implemented.');
  }

  /// 开始画中画
  Future<void> startPictureInPicture() {
    throw UnimplementedError('startPictureInPicture() has not been implemented.');
  }

  /// 停止画中画
  Future<void> stopPictureInPicture() {
    throw UnimplementedError('stopPictureInPicture() has not been implemented.');
  }

  Future<void> setLoggingEnabled(bool enabled) {
    throw UnimplementedError('setLoggingEnabled() has not been implemented.');
  }
}
