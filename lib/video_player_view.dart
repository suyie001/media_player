import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
