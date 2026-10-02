import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

Future<void>? _loading;
Future<void> _load() {
  if (web.window.has('easyplayMaterialColors')) return Future.value();
  return _loading ??= () async {
    final done = Completer<void>();
    final script = web.HTMLScriptElement()
      ..src = Uri.parse(
        web.document.baseURI,
      ).resolve('material_colors.js').toString();
    script.onload = ((web.Event _) => done.complete()).toJS;
    script.onerror = ((web.Event _) => done.completeError(
      StateError('主题配色资源加载失败'),
    )).toJS;
    web.document.head!.appendChild(script);
    try {
      await done.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      script.remove();
      _loading = null;
      rethrow;
    } finally {
      script.onload = null;
      script.onerror = null;
    }
  }();
}

Future<List<dynamic>> generateMaterialColors(
  Map<String, Object> request,
) async {
  await _load();
  final encoded = web.window.callMethod<JSString>(
    'easyplayMaterialColors'.toJS,
    jsonEncode(request).toJS,
  );
  return jsonDecode(encoded.toDart) as List<dynamic>;
}
