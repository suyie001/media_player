import 'package:flutter/material.dart';
import 'package:media_player/media_player.dart';
import 'package:media_player/media_player_platform_interface.dart';

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

class _MyHomePageState extends State<MyHomePage> {
  final _player = MediaPlayer();
  MediaItem? _currentItem;
  PlaybackState _playbackState = PlaybackState.none;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  List<MediaItem> _playlist = [];

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    await _player.initialize();

    // 设置示例播放列表
    final playlist = [
      MediaItem(
        id: '1',
        title: 'Jazz in Paris',
        url: 'https://storage.googleapis.com/exoplayer-test-media-0/Jazz_In_Paris.mp3',
        artist: 'Artist 1',
        album: 'Album 1',
        duration: const Duration(minutes: 3, seconds: 30),
        artworkUrl: 'https://rabbit-u.oss-cn-hangzhou.aliyuncs.com/uploadfile/20240702/666699915832905728.jpg',
      ),
      MediaItem(
        id: '2',
        title: '兔兔',
        url: 'http://oss-api-audio.zuidie.net/audio/MP4L/7f12cb0dc07148898ef5b949e84b2eb6.mp4',
        artist: 'Artist 2',
        album: 'Album 2',
        duration: const Duration(minutes: 4, seconds: 15),
        artworkUrl: 'https://rabbit-u.oss-cn-hangzhou.aliyuncs.com/uploadfile/20240702/666699915832905728.jpg',
      ),
      MediaItem(
        id: '3',
        title: '花絮1',
        url: 'http://oss-api-audio.zuidie.net/audio/MP3L/637f0001a2b8485faf78460c2367d3cc.mp3',
        artist: 'Artist 2',
        album: '没出息',
        duration: const Duration(minutes: 4, seconds: 15),
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
        title: '无损',
        url: 'http://oss-api-audio.zuidie.net/audio/FLAC/94703ba232f343a6b4a0c970c6eaa6d1.flac',
        artist: 'Artist 2',
        album: '没出息',
        duration: const Duration(minutes: 4, seconds: 15),
        artworkUrl: 'https://rabbit-u.oss-cn-hangzhou.aliyuncs.com/uploadfile/20240702/666699915832905728.jpg',
      ),
    ];

    // 监听播放状态变化
    _player.playbackStateStream.listen((state) {
      print('播放状态: ${state.name}');
      setState(() => _playbackState = state);
    });

    // 监听当前媒体项变化
    _player.mediaItemStream.listen((item) {
      print('当前媒体项: ${item?.title},id: ${item?.id}');
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
    await _player.setPlaylist(playlist);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Media Player Demo'),
      ),
      body: Column(
        children: [
          // 当前播放项信息
          if (_currentItem != null) ...[
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
                      value: _position.inMilliseconds.toDouble(),
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
            ],
          ),

          // 播放列表
          const SizedBox(height: 20),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _playlist.length,
              itemBuilder: (context, index) {
                final item = _playlist[index];
                final isPlaying = item.id == _currentItem?.id;

                return ListTile(
                  title: Text(
                    item.title,
                    style: TextStyle(
                      fontWeight: isPlaying ? FontWeight.bold : null,
                    ),
                  ),
                  subtitle: item.artist != null ? Text(item.artist!) : null,
                  leading: isPlaying ? const Icon(Icons.music_note, color: Colors.blue) : const SizedBox(width: 24),
                  onTap: () async {
                    await _player.setPlaylist(_playlist);
                    for (var i = 0; i < index; i++) {
                      await _player.skipToNext();
                    }
                    await _player.play();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
