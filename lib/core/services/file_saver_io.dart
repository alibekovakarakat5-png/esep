import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> saveAndShareFile(
  List<int> bytes,
  String fileName, {
  String? subject,
}) async {
  final dir = await getTemporaryDirectory();
  final filePath = '${dir.path}/$fileName';
  final file = File(filePath);
  await file.writeAsBytes(bytes);

  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(filePath)],
      subject: subject ?? fileName,
    ),
  );
}
