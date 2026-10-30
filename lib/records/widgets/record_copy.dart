import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Copies the complete record without passing through a platform file picker.
/// A selectable fallback also works when the browser denies clipboard access.
Future<void> copyRecordText(
  BuildContext context, {
  required String text,
  required String label,
}) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label已复制')));
  } catch (_) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('无法自动复制'),
        content: SizedBox(
          width: 560,
          height: MediaQuery.sizeOf(context).height * .55,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('可长按或拖动选择下方棋谱内容并复制。'),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    text,
                    key: const ValueKey('record-copy-fallback'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
