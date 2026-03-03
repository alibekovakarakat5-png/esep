import 'dart:js_interop';

import 'package:web/web.dart' as web;

void downloadFile({
  required List<int> bytes,
  required String filename,
  required String mimeType,
}) {
  final jsArray = bytes.map((b) => b.toJS).toList().toJS;
  final blob = web.Blob(jsArray, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);

  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;

  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();

  web.URL.revokeObjectURL(url);
}
