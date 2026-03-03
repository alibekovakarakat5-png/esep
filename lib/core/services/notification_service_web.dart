import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool isNotificationSupported() {
  try {
    // Если Notification.permission доступен — API поддерживается
    final _ = web.Notification.permission;
    return true;
  } catch (_) {
    return false;
  }
}

String getPermissionStatus() {
  try {
    return web.Notification.permission;
  } catch (_) {
    return 'denied';
  }
}

Future<bool> requestPermission() async {
  try {
    // requestPermission() возвращает JSPromise<JSString>
    final jsResult = await web.Notification.requestPermission().toDart;
    return jsResult.toDart == 'granted';
  } catch (_) {
    return false;
  }
}

void showNotification({
  required String title,
  required String body,
  String? tag,
  String? url,
}) {
  try {
    final options = web.NotificationOptions(
      body: body,
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      tag: tag ?? 'esep',
    );
    web.Notification(title, options);
  } catch (_) {}
}
