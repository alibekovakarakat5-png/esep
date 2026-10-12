import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/user_mode_provider.dart';
import 'onboarding_screen.dart';

String welcomeRole(String? value) =>
    const ['own', 'clients'].contains(value) ? value! : 'unknown';

/// Public entry explains the next step. URL hints never change an account role.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key, this.roleHint});
  final String? roleHint;
  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  late String _role = welcomeRole(widget.roleHint);
  bool _busy = false;
  String? _error;

  Future<void> _continue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Hive.box('settings').put('onboarding_done', true);
      if (!mounted) return;
      ref.read(hasSeenOnboardingProvider.notifier).state = true;
      if (ref.read(authProvider) != AuthState.authenticated) {
        context.go('/auth?welcome=$_role');
      } else if (_role == 'clients') {
        ref.read(userModeProvider.notifier).set(UserMode.accountant);
        context.go('/accountant');
      } else {
        context.go('/mode-select?role=own');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Не удалось продолжить. Попробуйте ещё раз.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients = _role == 'clients';
    return Scaffold(
      appBar: AppBar(title: const Text('С чего начать в Esep')),
      body: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Text('Одна задача — понятный следующий шаг',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          const Text(
              'Esep помогает собрать рабочую информацию в одном месте и продолжить с того, что уже сделано. Выберите, для кого ведёте учёт.'),
          const SizedBox(height: 20),
          Wrap(spacing: 10, runSpacing: 10, children: [
            ChoiceChip(
                label: const Text('Для своего бизнеса'),
                selected: _role == 'own',
                onSelected:
                    _busy ? null : (_) => setState(() => _role = 'own')),
            ChoiceChip(
                label: const Text('Я бухгалтер'),
                selected: clients,
                onSelected:
                    _busy ? null : (_) => setState(() => _role = 'clients')),
            ChoiceChip(
                label: const Text('Пока посмотреть'),
                selected: _role == 'unknown',
                onSelected:
                    _busy ? null : (_) => setState(() => _role = 'unknown')),
          ]),
          const SizedBox(height: 24),
          if (_role != 'unknown') ...[
            Text(
                clients
                    ? 'Начните с одного клиента'
                    : 'Начните с одной операции',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(clients
                ? '1. Добавьте клиента в разделе «Клиенты».\n2. Откройте его карточку и отметьте полученные документы.\n3. Вернитесь к списку, чтобы увидеть, что ещё требует внимания.'
                : '1. Укажите ИП или ТОО — отдельно от налогового режима.\n2. Добавьте доход или расход либо загрузите поддерживаемую выписку.\n3. Проверьте запись: сумму, дату и назначение.'),
            const SizedBox(height: 12),
            Text(clients
                ? 'Результат: первая карточка клиента, к которой можно вернуться.'
                : 'Результат: реальные операции в учёте вместо пустого экрана.'),
            const SizedBox(height: 20),
            FilledButton(
                onPressed: _busy ? null : _continue,
                child: Text(_busy
                    ? 'Открываем…'
                    : clients
                        ? 'Перейти к клиентам'
                        : 'Начать учёт своего бизнеса')),
          ] else
            const Text(
                'Для своего бизнеса — доходы, расходы и счета. Для бухгалтера — клиенты и отметки по документам. Выбор выше покажет конкретный первый шаг; регистрация нужна только для работы в кабинете.'),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(top: 12), child: Text(_error!)),
          const SizedBox(height: 24),
          const ExpansionTile(
              title: Text('Я пришёл из Telegram. Где мои списки?'),
              children: [
                Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        'Списки и напоминания бота остаются в Telegram. Здесь сохранено только направление входа, а перенос документов и переписки пока не подключён. Не создавайте дубликаты в ожидании автоматической синхронизации.'))
              ]),
          const ExpansionTile(
              title: Text('Можно ли доверить Esep налоги?'),
              children: [
                Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        'Расчёт зависит от режима, периода и особенностей компании. Проверьте исходные данные и применимость правил перед оплатой или сдачей отчётности. Свободный ИИ-консультант здесь пока не включён; Esep не гарантирует отсутствие штрафов.'))
              ]),
          const ExpansionTile(
              title: Text('Я ещё не знаю, ИП у меня или ТОО / какой режим'),
              children: [
                Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        'Не выбирайте наугад. Форма бизнеса и налоговый режим — разные сведения. Уточните их в своих регистрационных данных или у бухгалтера. Для знакомства с возможностями это не требуется.'))
              ]),
        ]),
      )),
    );
  }
}
