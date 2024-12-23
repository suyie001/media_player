import 'media_player_platform_interface.dart';
import 'media_player_event_channel.dart';

export 'media_player_platform_interface.dart';
export 'video_player_view.dart';

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

  /// 获取媒体时长流
  Stream<Duration> get durationStream => _eventChannel.durationStream;

  /// 获取缓冲进度流
  Stream<double> get bufferStream => _eventChannel.bufferStream;

  /// 获取缓冲状态流
  Stream<bool> get bufferingStream => _eventChannel.bufferingStream;

  /// 获取播放完成流
  Stream<bool> get completedStream => _eventChannel.completedStream;

  /// 获取错误流
  Stream<String> get errorStream => _eventChannel.errorStream;

  /// 获取播放模式变化流
  Stream<PlayMode> get playModeStream => _eventChannel.playModeStream;

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

  /// 添加一个媒体项到播放列表
  Future<void> add(MediaItem mediaItem) {
    return MediaPlayerPlatform.instance.add(mediaItem);
  }

  /// 从播放列表中移除指定位置的媒体项
  Future<void> removeAt(int index) {
    return MediaPlayerPlatform.instance.removeAt(index);
  }

  /// 在指定位置插入一个媒体项
  Future<void> insertAt(int index, MediaItem mediaItem) {
    return MediaPlayerPlatform.instance.insertAt(index, mediaItem);
  }

  /// 移动播放列表中的媒体项
  Future<void> move(int from, int to) {
    return MediaPlayerPlatform.instance.move(from, to);
  }

  /// 跳转到指定位置的媒体项
  Future<void> jumpTo(int index) {
    return MediaPlayerPlatform.instance.jumpTo(index);
  }

  /// 设置播放模式
  Future<void> setPlayMode(PlayMode mode) {
    return MediaPlayerPlatform.instance.setPlayMode(mode);
  }

  /// 获取当前播放模式
  Future<PlayMode> getPlayMode() {
    return MediaPlayerPlatform.instance.getPlayMode();
  }

  Future<void> showVideoView() async {
    await MediaPlayerPlatform.instance.play();
    return MediaPlayerPlatform.instance.showVideoView();
  }

  Future<void> hideVideoView() {
    return MediaPlayerPlatform.instance.hideVideoView();
  }

  Future<void> updateCurrentUrl(String url) async {
    return MediaPlayerPlatform.instance.updateCurrentUrl(url);
  }

  Future<void> startPictureInPicture() async {
    await MediaPlayerPlatform.instance.startPictureInPicture();
  }

  Future<void> stopPictureInPicture() async {
    await MediaPlayerPlatform.instance.stopPictureInPicture();
  }
}
