// Stub для не-веб платформ (Android, iOS, desktop)

bool isNotificationSupported() => false;

String getPermissionStatus() => 'denied';

Future<bool> requestPermission() async => false;

void showNotification({
  required String title,
  required String body,
  String? tag,
  String? url,
}) {}
