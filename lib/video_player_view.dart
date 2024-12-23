import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'media_player_method_channel.dart';

class VideoPlayerView extends StatelessWidget {
  const VideoPlayerView({super.key, required this.onPlatformViewCreated});
  // 回调
  final Function(int) onPlatformViewCreated;
  @override
  Widget build(BuildContext context) {
    // 根据平台返回不同的实现
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: 'media_player_video_view',
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (int id) {
          // 视图创建完成的回调
          // MethodChannelMediaPlayer().videoPlayerId(id);
          //todo id 通过回调传出去
          onPlatformViewCreated(id);
        },
      );
    }

    // Android 平台或其他平台的实现
    return Container();
  }
}
