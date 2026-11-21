import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'photo_review.dart';
import 'shared.dart';

class RegisterNameDialog extends StatefulWidget {
  const RegisterNameDialog({super.key, required this.api, this.store});
  final Backend api;
  final Json? store;
  @override
  State<RegisterNameDialog> createState() => _RegisterNameDialogState();
}

class _RegisterNameDialogState extends State<RegisterNameDialog> {
  String name = '';
  String? error;
  bool saving = false;

  Future<void> save() async {
    if (saving || name.trim().isEmpty) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final path = widget.store == null
          ? '/api/stores'
          : '/api/stores/${part(widget.store!['id'])}/suppliers';
      final row = await widget.api.post(path, {'name': name.trim()});
      if (mounted) Navigator.pop(context, row);
    } catch (e) {
      if (mounted)
        setState(() {
          saving = false;
          error = userErrorText(e);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.store == null ? '점포' : '거래처';
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: Text('$label 직접 등록'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.store != null) Text('등록할 점포 · ${widget.store!['name']}'),
          TextField(
              autofocus: true,
              enabled: !saving,
              maxLength: 150,
              decoration: InputDecoration(labelText: '$label 이름'),
              onChanged: (value) => setState(() => name = value),
              onSubmitted: (_) => save()),
          if (error != null) Text(error!),
        ]),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('취소')),
          FilledButton(
              onPressed: saving || name.trim().isEmpty ? null : save,
              child: Text(saving ? '등록 중' : '등록')),
        ],
      ),
    );
  }
}

Future<void> openSampleDelivery(BuildContext context, Backend api) async {
  try {
    final samples = records(await api.get('/api/sample-deliveries'), 'samples');
    if (!context.mounted) return;
    if (samples.isEmpty) {
      notify(context, '사용할 예시 명세표가 없습니다.');
      return;
    }
    final sample = await showModalBottomSheet<Json>(
      context: context,
      builder: (ctx) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
        const ListTile(
            title: Text('예시 명세표 선택'),
            subtitle: Text('원본을 판독한 뒤 저장할 점포를 확인하세요.')),
        for (final row in samples)
          ListTile(
              title: Text('${object(row['stores'])['name']} · ${row['item']}'),
              subtitle:
                  Text('${row['code']} · ${object(row['suppliers'])['name']}'),
              onTap: () => Navigator.pop(ctx, row)),
      ])),
    );
    if (sample == null || !context.mounted) return;
    final file =
        object(await api.get('/api/sample-deliveries/${part(sample['code'])}'));
    final bytes = base64Decode(file['image'] as String);
    if (!context.mounted) return;
    final route = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => PhotoReview(
          PlatformFile(
              name: file['filename'] as String,
              size: bytes.length,
              bytes: bytes),
          api: api),
    ));
    if (route != null && context.mounted) context.go(route);
  } catch (e) {
    if (context.mounted) notify(context, e);
  }
}
