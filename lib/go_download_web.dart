import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<bool> downloadSgf(Uint8List bytes, String fileName) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(
      type: fileName.toLowerCase().endsWith('.json')
          ? 'application/json;charset=utf-8'
          : 'application/x-go-sgf;charset=utf-8',
    ),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  // Browsers expose download initiation, not whether the user saved the file.
  return true;
}
