// FeedbackService — отправка отзывов от бета-тестировщиков на сервер.
//
// Бэк проверяет что пользователь имеет роль is_beta_tester и кладёт
// сообщение в БД + шлёт админу в Telegram. Обычные клиенты сюда не
// должны попадать — UI кнопку им не показывает, а если как-то попадут,
// сервер ответит 403.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'api_client.dart';

class FeedbackService {
  /// severity: 'low' | 'normal' | 'high' | 'critical'
  static Future<void> send({
    required String screen,
    required String message,
    String severity = 'normal',
    String? appVersion,
  }) async {
    final deviceInfo = _deviceInfo();
    await ApiClient.post('/feedback', {
      'screen': screen,
      'message': message,
      'severity': severity,
      if (appVersion != null && appVersion.isNotEmpty) 'appVersion': appVersion,
      'deviceInfo': deviceInfo,
    });
  }

  static Map<String, dynamic> _deviceInfo() {
    if (kIsWeb) {
      return {'platform': 'web'};
    }
    try {
      return {
        'platform': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'locale': Platform.localeName,
      };
    } catch (_) {
      return {};
    }
  }
}
