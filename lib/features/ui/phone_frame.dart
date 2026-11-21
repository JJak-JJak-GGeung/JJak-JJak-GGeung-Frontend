import 'package:flutter/material.dart';

import 'shared.dart';

/// Shows the whole app inside a phone-sized frame on wide screens so the
/// web page looks like the Android app: app bar, bottom buttons, the
/// floating upload button, sheets and dialogs all stay inside the frame.
/// On phones (or any window narrower than [_breakpoint]) it adds nothing.
class PhoneFrame extends StatelessWidget {
  const PhoneFrame({super.key, required this.child});
  final Widget child;

  static const _width = 430.0; // large phone width in logical pixels
  static const _maxHeight = 932.0;
  static const _breakpoint = 600.0;
  static const _margin = 24.0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    if (size.width < _breakpoint) return child;
    final roomy = size.height >= 720;
    final height = roomy ? (size.height - _margin * 2).clamp(0.0, _maxHeight) : size.height;
    final radius = roomy ? 28.0 : 0.0;
    return ColoredBox(
      color: const Color(0xffe4e8f0),
      child: Center(
        child: Container(
          width: _width,
          height: height,
          decoration: BoxDecoration(
            color: Palette.canvas,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Palette.line),
            boxShadow: const [
              BoxShadow(color: Color(0x22172538), blurRadius: 32, offset: Offset(0, 12)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          // Screens, sheets and dialogs size themselves from MediaQuery, so
          // report the frame as the whole screen.
          child: MediaQuery(
            data: media.copyWith(
              size: Size(_width, height),
              padding: EdgeInsets.zero,
              viewPadding: EdgeInsets.zero,
              viewInsets: EdgeInsets.zero,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
