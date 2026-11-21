import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Draw the evidence on the same fitted image the owner pans and zooms.
class OriginalPhoto extends StatefulWidget {
  const OriginalPhoto({super.key, required this.bytes, required this.location});

  final Uint8List bytes;
  final Map<String, dynamic> location;

  @override
  State<OriginalPhoto> createState() => _OriginalPhotoState();
}

class _OriginalPhotoState extends State<OriginalPhoto> {
  ui.Image? image;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    _decode(widget.bytes);
  }

  @override
  void didUpdateWidget(OriginalPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes) {
      image?.dispose();
      image = null;
      failed = false;
      _decode(widget.bytes);
    }
  }

  Future<void> _decode(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        if (!mounted || widget.bytes != bytes) {
          frame.image.dispose();
          return;
        }
        setState(() => image = frame.image);
      } finally {
        codec.dispose();
      }
    } catch (_) {
      if (mounted && widget.bytes == bytes) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    image?.dispose();
    super.dispose();
  }

  Rect? _region(Size size) {
    final coords = widget.location['region'];
    if (coords is! List ||
        coords.length != 4 ||
        !coords.every((v) => v is num && v.isFinite)) return null;
    final rect = Rect.fromLTRB(
      coords[0].toDouble(),
      coords[1].toDouble(),
      coords[2].toDouble(),
      coords[3].toDouble(),
    );
    if (rect.isEmpty ||
        rect.left < 0 ||
        rect.top < 0 ||
        rect.right > size.width ||
        rect.bottom > size.height) return null;
    return rect;
  }

  @override
  Widget build(BuildContext context) {
    final source = image;
    if (failed) return const Center(child: Text('원본 사진을 표시하지 못했습니다.'));
    if (source == null) return const Center(child: CircularProgressIndicator());
    final size = Size(source.width.toDouble(), source.height.toDouble());
    final rect = _region(size);
    return Column(children: [
      if (rect == null && widget.location.isNotEmpty)
        const Padding(
            padding: EdgeInsets.all(8), child: Text('원본에 표시할 위치 정보가 없습니다.')),
      Expanded(child: LayoutBuilder(builder: (context, constraints) {
        final fitted =
            applyBoxFit(BoxFit.contain, size, constraints.biggest).destination;
        final scale = fitted.width / size.width;
        return InteractiveViewer(
          maxScale: 5,
          child: Center(
              child: SizedBox.fromSize(
            size: fitted,
            child: Stack(fit: StackFit.expand, children: [
              RawImage(image: source, fit: BoxFit.fill),
              if (rect != null)
                Positioned.fromRect(
                  rect: Rect.fromLTRB(rect.left * scale, rect.top * scale,
                      rect.right * scale, rect.bottom * scale),
                  child: Semantics(
                      label: '선택한 원본 위치',
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0x20ffb200),
                          border: Border.all(
                              color: const Color(0xffaf4700), width: 2),
                        ),
                      )),
                ),
            ]),
          )),
        );
      })),
    ]);
  }
}
