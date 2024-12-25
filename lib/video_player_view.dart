import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';

import 'media_player_method_channel.dart';

class VideoPlayerView extends StatelessWidget {
  const VideoPlayerView({
    super.key,
    required this.onPlatformViewCreated,
    required this.onDispose,
  });

  final Function(int) onPlatformViewCreated;
  final VoidCallback onDispose;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _IOSVideoPlayer(
        onPlatformViewCreated: onPlatformViewCreated,
        onDispose: onDispose,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _AndroidVideoPlayer(
        onPlatformViewCreated: onPlatformViewCreated,
        onDispose: onDispose,
      );
    }
    return Container();
  }
}

// 创建一个有状态的 widget 来处理生命周期
class _IOSVideoPlayer extends StatefulWidget {
  const _IOSVideoPlayer({
    required this.onPlatformViewCreated,
    required this.onDispose,
  });

  final Function(int) onPlatformViewCreated;
  final VoidCallback onDispose;

  @override
  State<_IOSVideoPlayer> createState() => _IOSVideoPlayerState();
}

class _IOSVideoPlayerState extends State<_IOSVideoPlayer> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UiKitView(
      viewType: 'media_player_video_view',
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: widget.onPlatformViewCreated,
    );
  }
}

class _AndroidVideoPlayer extends StatefulWidget {
  const _AndroidVideoPlayer({
    required this.onPlatformViewCreated,
    required this.onDispose,
  });

  final Function(int) onPlatformViewCreated;
  final VoidCallback onDispose;

  @override
  State<_AndroidVideoPlayer> createState() => _AndroidVideoPlayerState();
}

class _AndroidVideoPlayerState extends State<_AndroidVideoPlayer> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      // print('Video view size: ${context.size}');
    } // 在 build 方法中添加
    return Container(
      color: Colors.black,
      child: AndroidView(
        viewType: 'media_player_video_view',
        onPlatformViewCreated: widget.onPlatformViewCreated,
        creationParams: <String, dynamic>{
          'backgroundColor': Colors.black.value,
        },
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<VerticalDragGestureRecognizer>(() => VerticalDragGestureRecognizer()),
          Factory<HorizontalDragGestureRecognizer>(() => HorizontalDragGestureRecognizer()),
          Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
        },
      ),
    );
  }
}
