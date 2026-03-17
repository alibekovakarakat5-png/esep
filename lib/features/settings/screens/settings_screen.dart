import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/providers/company_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/user_mode_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static Color _modeColor(UserMode mode) {
    switch (mode) {
      case UserMode.ip: return EsepColors.primary;
      case UserMode.too: return const Color(0xFF0D9488);
      case UserMode.accountant: return const Color(0xFF7B2FBE);
    }
  }

  static IconData _modeIcon(UserMode mode) {
    switch (mode) {
      case UserMode.ip: return Icons.person_rounded;
      case UserMode.too: return Icons.business_rounded;
      case UserMode.accountant: return Icons.work_rounded;
    }
  }

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
      body: 'Esep будет напоминать о соцплатежах и 910 форме.',
      tag: 'test',
    );
  }

  void _showCompanyEditor() {
    final company = ref.read(companyProvider);
    final nameCtrl    = TextEditingController(text: company.name);
    final iinCtrl     = TextEditingController(text: company.iin);
    final addrCtrl    = TextEditingController(text: company.address ?? '');
    final phoneCtrl   = TextEditingController(text: company.phone ?? '');
    final emailCtrl   = TextEditingController(text: company.email ?? '');
    final bankCtrl    = TextEditingController(text: company.bankName ?? '');
    final iikCtrl     = TextEditingController(text: company.iik ?? '');
    final bikCtrl     = TextEditingController(text: company.bik ?? '');
    final kbeCtrl     = TextEditingController(text: company.kbe ?? '19');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 24, 16, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Данные компании / ИП',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Используются в ЭСФ и PDF-счетах',
                style: TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
            const SizedBox(height: 20),
            _field(nameCtrl,  'Название / ФИО ИП *', Iconsax.building),
            const SizedBox(height: 10),
            _field(iinCtrl,   'ИИН / БИН *', Iconsax.document,
                type: TextInputType.number),
            const SizedBox(height: 10),
            _field(addrCtrl,  'Адрес', Iconsax.location),
            const SizedBox(height: 10),
            _field(phoneCtrl, 'Телефон', Iconsax.call,
                type: TextInputType.phone),
            const SizedBox(height: 10),
            _field(emailCtrl, 'Email', Iconsax.sms,
                type: TextInputType.emailAddress),
            const Divider(height: 24),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Банковские реквизиты (для ЭСФ)',
                  style: TextStyle(fontSize: 12, color: EsepColors.textSecondary,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 10),
            _field(bankCtrl, 'Банк (напр. Kaspi Bank)', Iconsax.bank),
            const SizedBox(height: 10),
            _field(iikCtrl,  'ИИК (IBAN)', Iconsax.card),
            const SizedBox(height: 10),
            _field(bikCtrl,  'БИК', Iconsax.code),
            const SizedBox(height: 10),
            _field(kbeCtrl,  'КБе (обычно 19 для ИП)', Iconsax.tag,
                type: TextInputType.number),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                await ref.read(companyProvider.notifier).save(
                  name:     nameCtrl.text.trim(),
                  iin:      iinCtrl.text.trim(),
                  address:  addrCtrl.text.trim().isEmpty ? null : addrCtrl.text.trim(),
                  phone:    phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                  email:    emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                  bankName: bankCtrl.text.trim().isEmpty ? null : bankCtrl.text.trim(),
                  iik:      iikCtrl.text.trim().isEmpty ? null : iikCtrl.text.trim(),
                  bik:      bikCtrl.text.trim().isEmpty ? null : bikCtrl.text.trim(),
                  kbe:      kbeCtrl.text.trim().isEmpty ? null : kbeCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Сохранить'),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {TextInputType? type}) =>
      TextField(
        controller: ctrl,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final reminders = NotificationService.getUpcomingReminders();
    final company = ref.watch(companyProvider);
    final mode = ref.watch(userModeProvider) ?? UserMode.ip;

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── Режим работы ─────────────────────────────────────────────────
          const _SectionHeader(title: 'Режим работы'),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _modeColor(mode).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _modeIcon(mode),
                  color: _modeColor(mode),
                  size: 20,
                ),
              ),
              title: Text(
                '${mode.label} — ${mode.description}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              subtitle: const Text('Нажмите чтобы сменить режим',
                  style: TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
              trailing: const Icon(Icons.swap_horiz_rounded, color: EsepColors.primary),
              onTap: () {
                ref.read(userModeProvider.notifier).clear();
                context.go('/mode-select');
              },
            ),
          ),
          const SizedBox(height: 20),

          // ── Данные компании ──────────────────────────────────────────────
          const _SectionHeader(title: 'Моя компания / ИП'),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: EsepColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Iconsax.building, color: EsepColors.primary, size: 20),
              ),
              title: Text(
                company.name.isEmpty ? 'Не заполнено' : company.name,
                style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w500,
                  color: company.name.isEmpty ? EsepColors.textDisabled : EsepColors.textPrimary,
                ),
              ),
              subtitle: Text(
                company.iin.isEmpty
                    ? 'Нажмите чтобы заполнить данные для ЭСФ'
                    : 'ИИН/БИН: ${company.iin}${company.iik != null ? ' · ИИК: ${company.iik}' : ''}',
                style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary),
              ),
              trailing: const Icon(Icons.chevron_right, color: EsepColors.textSecondary),
              onTap: _showCompanyEditor,
            ),
          ),
          if (!company.isComplete) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: EsepColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(children: [
                Icon(Iconsax.warning_2, color: EsepColors.warning, size: 14),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Заполните данные компании для генерации ЭСФ',
                    style: TextStyle(fontSize: 11, color: EsepColors.warning),
                  ),
                ),
              ]),
            ),
          ],

          // ── Уведомления ──────────────────────────────────────────────────
          const SizedBox(height: 20),
          const _SectionHeader(title: 'Уведомления'),
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
                          : _notificationsEnabled ? 'Включены' : 'Выключены')
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
          const SizedBox(height: 8),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Когда приходят напоминания',
                    style: TextStyle(fontSize: 12, color: EsepColors.textSecondary,
                        fontWeight: FontWeight.w600)),
                SizedBox(height: 10),
                _ReminderScheduleRow(
                  icon: Iconsax.calendar_1,
                  color: EsepColors.warning,
                  title: 'Соцплатежи (ОПВ+СО+ВОСМС)',
                  subtitle: 'За 7 и 3 дня до 25-го числа',
                ),
                SizedBox(height: 6),
                _ReminderScheduleRow(
                  icon: Iconsax.document_text,
                  color: EsepColors.info,
                  title: '910 форма',
                  subtitle: 'За 30, 7 и 3 дня (15 авг / 15 фев)',
                ),
              ]),
            ),
          ),

          // ── Дедлайны ─────────────────────────────────────────────────────
          if (reminders.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionHeader(title: 'Ближайшие дедлайны'),
            const SizedBox(height: 8),
            ...reminders.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: (r.daysLeft <= 3 ? EsepColors.expense : EsepColors.warning)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      r.type == DeadlineType.form910
                          ? Iconsax.document_text
                          : Iconsax.money_send,
                      color: r.daysLeft <= 3 ? EsepColors.expense : EsepColors.warning,
                      size: 18,
                    ),
                  ),
                  title: Text(r.title,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: Text(r.body,
                      style: const TextStyle(fontSize: 12, color: EsepColors.textSecondary)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (r.daysLeft <= 3 ? EsepColors.expense : EsepColors.warning)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${r.daysLeft} дн',
                        style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: r.daysLeft <= 3 ? EsepColors.expense : EsepColors.warning,
                        )),
                  ),
                ),
              ),
            )),
          ],

          // ── О приложении ──────────────────────────────────────────────────
          const SizedBox(height: 20),
          const _SectionHeader(title: 'О приложении'),
          const SizedBox(height: 8),
          const Card(
            child: Column(children: [
              _InfoTile(icon: Iconsax.info_circle, title: 'Версия', value: '1.0.0'),
              Divider(height: 1, indent: 56),
              _InfoTile(icon: Iconsax.shield_tick, title: 'Данные', value: 'Хранятся на сервере'),
              Divider(height: 1, indent: 56),
              _InfoTile(icon: Iconsax.flag, title: 'Налоговый кодекс', value: 'РК 2026'),
            ]),
          ),

          // ── Выход ─────────────────────────────────────────────────────────
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: EsepColors.expense.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Iconsax.logout, color: EsepColors.expense, size: 18),
              ),
              title: const Text('Выйти из аккаунта',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: EsepColors.expense)),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Выйти?'),
                    content: const Text('Вы будете перенаправлены на экран входа.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Выйти', style: TextStyle(color: EsepColors.expense)),
                      ),
                    ],
                  ),
                );
                if (ok == true && mounted) {
                  await ref.read(authProvider.notifier).logout();
                }
              },
            ),
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
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
        color: EsepColors.textPrimary),
  );
}

class _ReminderScheduleRow extends StatelessWidget {
  const _ReminderScheduleRow({
    required this.icon, required this.color,
    required this.title, required this.subtitle,
  });
  final IconData icon;
  final Color color;
  final String title, subtitle;

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6)),
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
    trailing: Text(value,
        style: const TextStyle(fontSize: 13, color: EsepColors.textSecondary)),
  );
}
