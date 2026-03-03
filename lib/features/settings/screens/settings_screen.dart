import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool get _notificationsEnabled => NotificationService.isEnabled;
  bool get _notificationsSupported => NotificationService.isSupported;
  String get _permission => NotificationService.permissionStatus;

  Future<void> _toggleNotifications(bool value) async {
    if (value) {
      final granted = await NotificationService.requestPermission();
      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Разрешение на уведомления отклонено. Включите в настройках браузера.'),
            backgroundColor: EsepColors.expense,
          ),
        );
      }
    } else {
      await NotificationService.setEnabled(false);
    }
    setState(() {});
  }

  Future<void> _testNotification() async {
    NotificationService.show(
      title: '✅ Уведомления работают!',
      body: 'Есеп будет напоминать о соцплатежах и 910 форме.',
      tag: 'test',
    );
  }

  @override
  Widget build(BuildContext context) {
    final reminders = NotificationService.getUpcomingReminders();

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Уведомления
          _SectionHeader(title: 'Уведомления'),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              SwitchListTile(
                value: _notificationsEnabled,
                onChanged: _notificationsSupported ? _toggleNotifications : null,
                activeTrackColor: EsepColors.primary,
                secondary: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: EsepColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Iconsax.notification, color: EsepColors.primary, size: 18),
                ),
                title: const Text('Напоминания о дедлайнах',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Text(
                  _notificationsSupported
                      ? (_permission == 'denied'
                          ? 'Заблокировано в браузере'
                          : _notificationsEnabled
                              ? 'Включены'
                              : 'Выключены')
                      : 'Не поддерживается в этом браузере',
                  style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary),
                ),
              ),
              if (_notificationsEnabled) ...[
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: EsepColors.income.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Iconsax.notification_bing, color: EsepColors.income, size: 18),
                  ),
                  title: const Text('Тест уведомления',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  subtitle: const Text('Отправить пробное уведомление',
                      style: TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
                  trailing: const Icon(Icons.chevron_right, color: EsepColors.textSecondary),
                  onTap: _testNotification,
                ),
              ],
            ]),
          ),

          // Расписание напоминаний
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Когда приходят напоминания',
                    style: TextStyle(fontSize: 12, color: EsepColors.textSecondary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                _ReminderScheduleRow(
                  icon: Iconsax.calendar_1,
                  color: EsepColors.warning,
                  title: 'Соцплатежи (ОПВ+СО+ВОСМС)',
                  subtitle: 'За 7 и 3 дня до 25-го числа',
                ),
                const SizedBox(height: 6),
                _ReminderScheduleRow(
                  icon: Iconsax.document_text,
                  color: EsepColors.info,
                  title: '910 форма',
                  subtitle: 'За 30, 7 и 3 дня (15 авг / 15 фев)',
                ),
              ]),
            ),
          ),

          // Активные дедлайны
          if (reminders.isNotEmpty) ...[
            const SizedBox(height: 20),
            _SectionHeader(title: 'Ближайшие дедлайны'),
            const SizedBox(height: 8),
            ...reminders.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: (r.daysLeft <= 3 ? EsepColors.expense : EsepColors.warning).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      r.type == DeadlineType.form910 ? Iconsax.document_text : Iconsax.money_send,
                      color: r.daysLeft <= 3 ? EsepColors.expense : EsepColors.warning,
                      size: 18,
                    ),
                  ),
                  title: Text(r.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: Text(r.body, style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (r.daysLeft <= 3 ? EsepColors.expense : EsepColors.warning).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${r.daysLeft} дн',
                      style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: r.daysLeft <= 3 ? EsepColors.expense : EsepColors.warning,
                      ),
                    ),
                  ),
                ),
              ),
            )),
          ],

          // О приложении
          const SizedBox(height: 20),
          _SectionHeader(title: 'О приложении'),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              _InfoTile(icon: Iconsax.info_circle, title: 'Версия', value: '1.0.0'),
              const Divider(height: 1, indent: 56),
              _InfoTile(icon: Iconsax.shield_tick, title: 'Данные', value: 'Хранятся локально'),
              const Divider(height: 1, indent: 56),
              _InfoTile(icon: Iconsax.flag, title: 'Налоговый кодекс', value: 'РК 2026'),
            ]),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: EsepColors.textPrimary),
  );
}

class _ReminderScheduleRow extends StatelessWidget {
  const _ReminderScheduleRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final Color color;
  final String title, subtitle;

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 28, height: 28,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Icon(icon, color: color, size: 14),
    ),
    const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      Text(subtitle, style: const TextStyle(fontSize: 11, color: EsepColors.textSecondary)),
    ])),
  ]);
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.title, required this.value});
  final IconData icon;
  final String title, value;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    leading: Icon(icon, size: 18, color: EsepColors.textSecondary),
    title: Text(title, style: const TextStyle(fontSize: 13)),
    trailing: Text(value, style: const TextStyle(fontSize: 13, color: EsepColors.textSecondary)),
  );
}
