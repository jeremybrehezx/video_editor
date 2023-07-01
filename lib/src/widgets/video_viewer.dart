import 'package:cached_video_player/cached_video_player.dart';
import 'package:flutter/material.dart';
import 'package:video_editor/src/controller.dart';

class VideoViewer extends StatelessWidget {
  const VideoViewer({super.key, required this.controller, this.child});

  final VideoEditorController controller;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (controller.video.value.isPlaying) {
          controller.video.pause();
        } else {
          controller.video.play();
        }
      },
      child: Center(
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: controller.video.value.aspectRatio,
              child: CachedVideoPlayer(controller.video),
            ),
            if (child != null)
              AspectRatio(
                aspectRatio: controller.video.value.aspectRatio,
                child: child,
              ),
          ],
        ),
      ),
    );
  }
}
