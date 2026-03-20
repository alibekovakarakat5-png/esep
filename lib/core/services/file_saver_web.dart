import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<void> saveAndShareFile(
  List<int> bytes,
  String fileName, {
  String? subject,
}) async {
  final data = Uint8List.fromList(bytes);
  final blob = web.Blob([data.toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
