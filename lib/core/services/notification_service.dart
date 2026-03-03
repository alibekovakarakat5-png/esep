import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

// Web-only imports
import 'notification_service_web.dart'
    if (dart.library.io) 'notification_service_stub.dart' as platform;

/// Типы дедлайнов для напоминаний
enum DeadlineType { socialPayment, form910, unpaidInvoice }

class DeadlineReminder {
  final DeadlineType type;
  final String title;
  final String body;
  final int daysLeft;
  final String route;

  const DeadlineReminder({
    required this.type,
    required this.title,
    required this.body,
    required this.daysLeft,
    required this.route,
  });
}

class NotificationService {
  NotificationService._();

  static const _settingsBox = 'settings';
  static const _keyEnabled = 'notificationsEnabled';
  static const _keyLastCheck = 'lastNotificationCheck';

  /// Включены ли уведомления (сохранено в Hive)
  static bool get isEnabled {
    final box = Hive.box(_settingsBox);
    return box.get(_keyEnabled, defaultValue: false) as bool;
  }

  /// Поддерживается ли Notification API в текущей среде
  static bool get isSupported => kIsWeb && platform.isNotificationSupported();

  /// Текущий статус разрешения ('default', 'granted', 'denied')
  static String get permissionStatus =>
      isSupported ? platform.getPermissionStatus() : 'denied';

  /// Запросить разрешение у пользователя
  static Future<bool> requestPermission() async {
    if (!isSupported) return false;
    final granted = await platform.requestPermission();
    if (granted) {
      Hive.box(_settingsBox).put(_keyEnabled, true);
    }
    return granted;
  }

  /// Сохранить настройку уведомлений
  static Future<void> setEnabled(bool value) async {
    if (value && permissionStatus != 'granted') {
      await requestPermission();
      return;
    }
    await Hive.box(_settingsBox).put(_keyEnabled, value);
  }

  /// Показать немедленное уведомление
  static void show({
    required String title,
    required String body,
    String? tag,
    String? url,
  }) {
    if (!isSupported || !isEnabled || permissionStatus != 'granted') return;
    platform.showNotification(title: title, body: body, tag: tag, url: url);
  }

  /// Проверить дедлайны и показать уведомления (вызывается при запуске)
  static void checkDeadlines() {
    if (!isEnabled || permissionStatus != 'granted') return;

    final box = Hive.box(_settingsBox);
    final lastCheck = box.get(_keyLastCheck) as DateTime?;
    final now = DateTime.now();

    // Не более одной проверки в день
    if (lastCheck != null &&
        lastCheck.year == now.year &&
        lastCheck.month == now.month &&
        lastCheck.day == now.day) {
      return;
    }

    box.put(_keyLastCheck, now);

    for (final reminder in _getActiveReminders(now)) {
      show(
        title: reminder.title,
        body: reminder.body,
        tag: reminder.type.name,
        url: reminder.route,
      );
    }
  }

  static List<DeadlineReminder> _getActiveReminders(DateTime now) {
    final reminders = <DeadlineReminder>[];

    // 1. Соцплатежи — 25-е каждого месяца
    const socialDay = 25;
    final socialDeadline = now.day <= socialDay
        ? DateTime(now.year, now.month, socialDay)
        : DateTime(now.year, now.month + 1, socialDay);
    final socialDays = socialDeadline.difference(now).inDays;

    if (socialDays <= 7) {
      reminders.add(DeadlineReminder(
        type: DeadlineType.socialPayment,
        title: '💰 Соцплатежи через $socialDays ${_days(socialDays)}',
        body: 'ОПВ + ОПВР + СО + ВОСМС — до 25 числа',
        daysLeft: socialDays,
        route: '/taxes',
      ));
    }

    // 2. 910 форма — 15 августа и 15 февраля
    final form910 = _next910Deadline(now);
    if (form910 <= 30) {
      reminders.add(DeadlineReminder(
        type: DeadlineType.form910,
        title: '📋 910 форма через $form910 ${_days(form910)}',
        body: 'Сдайте декларацию по упрощённому режиму',
        daysLeft: form910,
        route: '/taxes',
      ));
    }

    return reminders;
  }

  static int _next910Deadline(DateTime now) {
    DateTime next;
    if (now.month < 8 || (now.month == 8 && now.day <= 15)) {
      next = DateTime(now.year, 8, 15);
    } else {
      next = DateTime(now.year + 1, 2, 15);
    }
    return next.difference(now).inDays;
  }

  static String _days(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'день';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) return 'дня';
    return 'дней';
  }

  /// Получить все активные напоминания для отображения в UI
  static List<DeadlineReminder> getUpcomingReminders() {
    return _getActiveReminders(DateTime.now());
  }
}
