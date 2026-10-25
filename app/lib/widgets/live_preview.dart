import 'package:flutter/material.dart';

import '../vision/live_detection.dart';

/// Zeigt das Bild der [LiveDetection] (Kamera oder Demo-Szene) im richtigen Seitenverhältnis,
/// mit einem Overlay darüber, das die Bildgröße in Pixeln bekommt.
class LivePreview extends StatelessWidget {
  const LivePreview({super.key, required this.live, required this.overlay});

  final LiveDetection live;
  final Widget Function(BuildContext context, Size size) overlay;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: live,
      builder: (context, _) {
        final videoSize = live.videoSize;
        if (videoSize == null) return const Center(child: CircularProgressIndicator());
        final demo = live.demo;
        return Center(
          child: AspectRatio(
            aspectRatio: videoSize.width / videoSize.height,
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                fit: StackFit.expand,
                children: [
                  if (demo != null)
                    demo.image == null
                        ? const ColoredBox(color: Colors.black)
                        : RawImage(image: demo.image, fit: BoxFit.contain)
                  else
                    HtmlElementView(viewType: live.camera.viewType),
                  overlay(context, constraints.biggest),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
