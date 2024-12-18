import 'media_player_platform_interface.dart';
import 'media_player_event_channel.dart';

class MediaPlayer {
  static final MediaPlayer _instance = MediaPlayer._internal();

  factory MediaPlayer() {
    return _instance;
  }

  MediaPlayer._internal() {
    _eventChannel = MediaPlayerEventChannel();
  }

  late final MediaPlayerEventChannel _eventChannel;

  /// 获取播放状态流
  Stream<PlaybackState> get playbackStateStream => _eventChannel.playbackStateStream;

  /// 获取当前媒体项流
  Stream<MediaItem?> get mediaItemStream => _eventChannel.mediaItemStream;

  /// 获取播放列表变化流
  Stream<List<MediaItem>> get playlistStream => _eventChannel.playlistStream;

  /// 获取播放位置流
  Stream<Duration> get positionStream => _eventChannel.positionStream;

  /// 获取错误流
  Stream<String> get errorStream => _eventChannel.errorStream;

  /// 初始化播放器
  Future<void> initialize() {
    return MediaPlayerPlatform.instance.initialize();
  }

  /// 设置播放列表
  Future<void> setPlaylist(List<MediaItem> playlist) {
    return MediaPlayerPlatform.instance.setPlaylist(playlist);
  }

  /// 播放
  Future<void> play() {
    return MediaPlayerPlatform.instance.play();
  }

  /// 暂停
  Future<void> pause() {
    return MediaPlayerPlatform.instance.pause();
  }

  /// 停止
  Future<void> stop() {
    return MediaPlayerPlatform.instance.stop();
  }

  /// 跳转到指定位置
  Future<void> seekTo(Duration position) {
    return MediaPlayerPlatform.instance.seekTo(position);
  }

  /// 下一曲
  Future<void> skipToNext() {
    return MediaPlayerPlatform.instance.skipToNext();
  }

  /// 上一曲
  Future<void> skipToPrevious() {
    return MediaPlayerPlatform.instance.skipToPrevious();
  }

  /// 设置音量
  Future<void> setVolume(double volume) {
    return MediaPlayerPlatform.instance.setVolume(volume);
  }

  /// 获取当前播放状态
  Future<PlaybackState> getPlaybackState() {
    return MediaPlayerPlatform.instance.getPlaybackState();
  }

  /// 获取当前播放位置
  Future<Duration> getCurrentPosition() {
    return MediaPlayerPlatform.instance.getCurrentPosition();
  }

  /// 获取当前播放项
  Future<MediaItem?> getCurrentMediaItem() {
    return MediaPlayerPlatform.instance.getCurrentMediaItem();
  }
}
