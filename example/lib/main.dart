import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:harmony_plugin/harmony_plugin.dart';
import 'package:media_player/media_player.dart';
import 'package:permission_handler/permission_handler.dart';
// import 'package:media_player/media_player_platform_interface.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Media Player Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  int _videoPlayerId = 0;
  bool _isVideoViewVisible = false;
  final _player = MediaPlayer();
  MediaItem? _currentItem;
  PlaybackState _playbackState = PlaybackState.none;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  List<MediaItem> _playlist = [];
  PlayMode _playMode = PlayMode.list;
  double _playbackSpeed = 1.0;

  bool _isHarmony = false;
  bool _isPureMode = false;
  String _harmonyVersion = '';
  final _harmonyPlugin = HarmonyPlugin();
  @override
  void initState() {
    super.initState();
    // 监听应用生命周期
    WidgetsBinding.instance.addObserver(this);
    _checkHarmony();
    _requestNotificationPermission();
    _initializePlayer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
    } else if (state == AppLifecycleState.paused) {
      print('应用进入后台');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initializePlayer() async {
    await _player.initialize();

    // 设置示例播放列表
    final playlist = [
      MediaItem(
        id: '1',
        title: '花絮1',
        url: 'http://oss-api-audio.zuidie.net/audio/MP3L/637f0001a2b8485faf78460c2367d3cc.mp3',
        artist: 'Artist 2',
        album: '没出息',
        duration: const Duration(minutes: 4, seconds: 15),
        artworkUrl: 'https://rabbit-u.oss-cn-hangzhou.aliyuncs.com/uploadfile/20240702/666699915832905728.jpg',
      ),
      MediaItem(
        id: '2',
        title: 'Jazz in Paris',
        url: 'https://storage.googleapis.com/exoplayer-test-media-0/Jazz_In_Paris.mp3',
        artist: 'Artist 1',
        album: 'Album 1',
        duration: const Duration(minutes: 3, seconds: 30),
        artworkUrl: 'https://rabbit-u.oss-cn-hangzhou.aliyuncs.com/uploadfile/20240702/666699915832905728.jpg',
      ),
      MediaItem(
        id: '4',
        title: '高清',
        url: 'http://oss-api-audio.zuidie.net/audio/MP3H/94703ba232f343a6b4a0c970c6eaa6d1.mp3',
        artist: 'Artist 2',
        album: '没出息',
        duration: const Duration(minutes: 4, seconds: 15),
        artworkUrl: 'https://rabbit-u.oss-cn-hangzhou.aliyuncs.com/uploadfile/20240702/666699915832905728.jpg',
      ),
      MediaItem(
        id: '5',
        title: '普通',
        url: 'http://oss-api-audio.zuidie.net/audio/MP3L/94703ba232f343a6b4a0c970c6eaa6d1.mp3',
        artist: 'Artist 2',
        album: '没出息',
        duration: const Duration(minutes: 4, seconds: 15),
        artworkUrl: 'https://rabbit-u.oss-cn-hangzhou.aliyuncs.com/uploadfile/20240702/666699915832905728.jpg',
      ),
      MediaItem(
        id: '6',
        title: '视频',
        url: 'http://oss-api-audio.zuidie.net/audio/MP4L/7f12cb0dc07148898ef5b949e84b2eb6.mp4',
        duration: const Duration(minutes: 4, seconds: 15),
      ),
    ];

    // 监听播放状态变化
    _player.playbackStateStream.listen((state) {
      print('播放状态: ${state.name}');
      setState(() => _playbackState = state);
    });

    // 监听当前媒体项变化
    _player.mediaItemStream.listen((item) {
      print('当前媒体项: ${item?.title},id: ${item?.id} ${item?.url}');
      setState(() => _currentItem = item);
    });

    // 监听播放位置变化
    _player.positionStream.listen((position) {
      setState(() => _position = position);
    });

    // 监听播放列表变化
    _player.playlistStream.listen((playlist) {
      print('播放列表: ${playlist.map((e) => e.title).join(', ')}');
      setState(() => _playlist = playlist);
    });

    // 监听媒体时长变化
    _player.durationStream.listen((Duration duration) {
      setState(() {
        _duration = duration;
      });
    });

    // 监听播放完成
    _player.completedStream.listen((completed) {
      if (completed) {
        print('播放完成');
      }
    });

    // 监听缓冲进度
    _player.bufferStream.listen((progress) {
      print('缓冲进度: ${(progress * 100).toStringAsFixed(1)}%');
    });

    // 监听缓冲状态
    _player.bufferingStream.listen((isBuffering) {
      print('是否正在缓冲: $isBuffering');
    });

    // 监听错误
    _player.errorStream.listen((error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $error')),
      );
    });

    // 监听播放模式变化
    _player.playModeStream.listen((mode) {
      print('播放模式: ${mode.name}');
      setState(() {
        _playMode = mode;
      });
    });

    // 监听播放速度变化
    _player.speedStream.listen((speed) {
      print('播放速度: $speed');
      setState(() {
        _playbackSpeed = speed;
      });
    });

    await _player.setPlaylist(playlist);
  }

  Future<void> checkoutToAudio() async {
    Duration position = _position;
    // await _player.updateCurrentUrl('http://oss-api-audio.zuidie.net/audio/MP3L/94703ba232f343a6b4a0c970c6eaa6d1.mp3');
    await _player.seekTo(position);
    await _player.play();
  }

  Future<void> checkoutToVideo() async {
    Duration position = _position;
    //  await _player.updateCurrentUrl('http://oss-api-audio.zuidie.net/audio/MP4L/7f12cb0dc07148898ef5b949e84b2eb6.mp4');
    await _player.showVideoView();
    setState(() {
      _isVideoViewVisible = true;
    });
    await Future.delayed(const Duration(seconds: 1));
    print('seekTo: $position');
    await _player.seekTo(position);
  }

  moveMedia(int from, int to) {
    _player.move(from, to);
  }

  removeMedia(int index) {
    _player.removeAt(index);
  }

  @override
  Widget build(BuildContext context) {
    IconData playModeIcon;
    switch (_playMode) {
      case PlayMode.all:
        playModeIcon = Icons.all_inclusive;
        break;
      case PlayMode.list:
        playModeIcon = Icons.list;
        break;
      case PlayMode.one:
        playModeIcon = Icons.repeat_one;
        break;
      case PlayMode.shuffle:
        playModeIcon = Icons.shuffle;
        break;
    }
    print('isHarmony: $_isHarmony');
    print('isPureMode: $_isPureMode');
    print('harmonyVersion: $_harmonyVersion');
    return Scaffold(
      appBar: AppBar(
        title: Text('Media Player Demo $_playbackSpeed'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_in_picture),
            onPressed: () async {
              //获取悬浮窗权限
              bool isGranted = await _requestPictureInPicturePermission();
              print('isGranted: $isGranted');

              if (await _player.isPictureInPictureSupported()) {
                _player.startPictureInPicture();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PiP is not supported on this device')),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.speed),
            onPressed: () {
              if (_playbackSpeed == 1.0) {
                _player.setPlaybackSpeed(2.0);
              } else {
                _player.setPlaybackSpeed(1.0);
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 当前播放项信息
            if (_currentItem != null) ...[
              if (_isVideoViewVisible)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: AspectRatio(
                    aspectRatio: 16 / 9, // 或其他适合的宽高比
                    child: VideoPlayerView(
                      onPlatformViewCreated: (id) {
                        print('Video view created: $id');
                      },
                      onDispose: () {
                        print('Video view disposed');
                      },
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Text(
                _currentItem!.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (_currentItem!.artist != null)
                Text(
                  _currentItem!.artist!,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
            ],

            // 进度条
            if (_duration != Duration.zero) ...[
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(_formatDuration(_position)),
                    Expanded(
                      child: Slider(
                        value: min(_duration.inMilliseconds.toDouble(), _position.inMilliseconds.toDouble()),
                        max: _duration.inMilliseconds.toDouble(),
                        onChanged: (value) {
                          _player.seekTo(Duration(milliseconds: value.toInt()));
                        },
                      ),
                    ),
                    Text(_formatDuration(_duration)),
                  ],
                ),
              ),
            ],

            // 控制按钮
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(playModeIcon),
                  onPressed: () {
                    switch (_playMode) {
                      case PlayMode.list:
                        _player.setPlayMode(PlayMode.all);
                        break;
                      case PlayMode.all:
                        _player.setPlayMode(PlayMode.one);
                        break;
                      case PlayMode.one:
                        _player.setPlayMode(PlayMode.shuffle);
                        break;
                      case PlayMode.shuffle:
                        _player.setPlayMode(PlayMode.list);
                        break;
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: _player.skipToPrevious,
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: Icon(_playbackState == PlaybackState.playing ? Icons.pause : Icons.play_arrow),
                  onPressed: () {
                    if (_playbackState == PlaybackState.playing) {
                      _player.pause();
                    } else {
                      _player.play();
                    }
                  },
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: _player.skipToNext,
                ),
                IconButton(
                    onPressed: () async {
                      if (_isVideoViewVisible == false) {
                        await checkoutToVideo();
                      } else {
                        await checkoutToAudio();
                        setState(() {
                          _isVideoViewVisible = false;
                        });
                      }
                    },
                    icon: const Icon(Icons.video_library))
              ],
            ),
            const SizedBox(height: 20),
            const Divider(),
            Expanded(
              child: ReorderableListView.builder(
                itemCount: _playlist.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (oldIndex < newIndex) {
                      newIndex -= 1;
                    }
                    moveMedia(oldIndex, newIndex);
                  });
                },
                itemBuilder: (context, index) {
                  final item = _playlist[index];
                  final isPlaying = item.id == _currentItem?.id;

                  return ListTile(
                    key: ValueKey(item.id),
                    title: Text(
                      item.title,
                      style: TextStyle(
                        fontWeight: isPlaying ? FontWeight.bold : null,
                      ),
                    ),
                    subtitle: item.artist != null ? Text(item.artist!) : null,
                    leading: isPlaying ? const Icon(Icons.music_note, color: Colors.blue) : const SizedBox(width: 24),
                    trailing: const Icon(Icons.drag_handle),
                    onTap: () async {
                      await _player.jumpTo(index);
                      await _player.play();
                    },
                    // onLongPress: () {
                    //   showDialog(
                    //     context: context,
                    //     builder: (context) => AlertDialog(
                    //       title: const Text('删除'),
                    //       content: Text('是否删除 ${item.title}?'),
                    //       actions: [
                    //         TextButton(
                    //           onPressed: () => Navigator.pop(context),
                    //           child: const Text('取消'),
                    //         ),
                    //         TextButton(
                    //           onPressed: () {
                    //             Navigator.pop(context);
                    //             removeMedia(index);
                    //           },
                    //           child: const Text('删除'),
                    //         ),
                    //       ],
                    //     ),
                    //   );
                    // },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  Future<void> _requestNotificationPermission() async {
    // 检查当前权限状态
    final status = await Permission.notification.status;

    if (status.isDenied) {
      // 如果权限被拒绝，请求权限
      final result = await Permission.notification.request();

      if (result.isPermanentlyDenied) {
        // 如果用户永久拒绝了权限，提示用户去设置中心开启
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('需要通知权限'),
              content: const Text('请在设置中开启通知权限，以便接收媒体播放控制和通知'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    openAppSettings();
                  },
                  child: const Text('去设置'),
                ),
              ],
            ),
          );
        }
      }
    }
  }

  // 可选：添加一个检查权限的方法
  Future<bool> _checkNotificationPermission() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }

  // 可选：添加一个手动请求权限的方法
  Future<void> _manualRequestPermission() async {
    final status = await Permission.notification.request();
    if (status.isPermanentlyDenied && mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('需要通知权限'),
          content: const Text('请在设置中开启通知权限'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              child: const Text('去设置'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _checkHarmony() async {
    if (Platform.isIOS) {
      return;
    }
    bool isHarmony;
    bool isPureMode;
    String harmonyVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    try {
      isHarmony = await _harmonyPlugin.isHarmonyOS();
      harmonyVersion = await _harmonyPlugin.getHarmonyVersion();
      isPureMode = await _harmonyPlugin.isHarmonyPureMode();
    } on PlatformException {
      isHarmony = false;
      harmonyVersion = '';
      isPureMode = false;
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _isHarmony = isHarmony;
      _harmonyVersion = harmonyVersion;
      _isPureMode = isPureMode;
    });
  }

  Future<bool> _requestPictureInPicturePermission() async {
    if (Platform.isIOS) {
      return true;
    }
    PermissionStatus status = await Permission.systemAlertWindow.status;
    if (status.isDenied) {
      await Permission.systemAlertWindow.request();
    }
    return status.isGranted;
  }
}
