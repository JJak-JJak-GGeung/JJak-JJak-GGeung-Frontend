import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class StartButton extends StatelessWidget {
  const StartButton(
      {super.key,
      this.enabled = true,
      this.draft = false,
      this.returnRoute = false});

  final bool enabled;
  final bool draft;
  final bool returnRoute;

  Future<void> _leave(BuildContext context) async {
    if (draft) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('저장하지 않고 처음으로 갈까요?'),
          content: const Text('지금 검토 중인 내용은 저장되지 않습니다.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('계속 확인')),
            TextButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('처음으로 이동')),
          ],
        ),
      );
      if (discard != true || !context.mounted) return;
    }
    if (returnRoute) {
      Navigator.pop(context, '/');
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: '처음으로',
        icon: const Icon(Icons.home_outlined),
        onPressed: enabled ? () => _leave(context) : null,
      );
}
