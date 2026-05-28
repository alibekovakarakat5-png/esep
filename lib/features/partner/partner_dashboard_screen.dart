/// Partner Dashboard — кабинет партнёра (бухгалтерская фирма).
///
/// Показывает:
///   - Заработок этот месяц / всего
///   - Активные клиенты + прогноз
///   - Список промокодов с активациями
///   - Кнопка «Создать промокод»
///
/// Дизайн в едином языке с business.esepkz.com / Platform Dashboard.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/services/api_client.dart';

class _Brand {
  static const Color bgPage       = Color(0xFFFAFBFD);
  static const Color bgDark       = Color(0xFF0B1426);
  static const Color cardDark     = Color(0xFF14213D);
  static const Color cardDarkAlt  = Color(0xFF1E2D4F);
  static const Color borderDark   = Color(0xFF1F2D4D);
  static const Color cardLight    = Colors.white;
  static const Color border       = Color(0xFFE4E9F2);
  static const Color text         = Color(0xFF0B1426);
  static const Color textSecondary= Color(0xFF5A6986);
  static const Color textOnDark   = Colors.white;
  static const Color textDim      = Color(0xFF98A4C0);
  static const Color accent       = Color(0xFF1E5BFF);
  static const Color accentBright = Color(0xFF6A8DFF);
  static const Color green        = Color(0xFF00B870);
  static const Color greenBright  = Color(0xFF6CE2A8);
  static const Color orange       = Color(0xFFF59E0B);
  static const Color tagBg        = Color(0xFFEBF1FF);

  static const double maxWidth = 1280.0;
}

class PartnerDashboardScreen extends ConsumerStatefulWidget {
  const PartnerDashboardScreen({super.key});

  @override
  ConsumerState<PartnerDashboardScreen> createState() =>
      _PartnerDashboardScreenState();
}

class _PartnerDashboardScreenState
    extends ConsumerState<PartnerDashboardScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get('/partner/dashboard');
      setState(() {
        _data = (res is Map) ? Map<String, dynamic>.from(res) : null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _generatePromo() async {
    try {
      await ApiClient.post('/partner/promos/generate', {});
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Промокод создан'),
          backgroundColor: _Brand.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Скопировано: $code'),
        backgroundColor: _Brand.accent,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Brand.bgPage,
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _Brand.accent))
                : _error != null
                    ? _buildError()
                    : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _Brand.border, width: 1)),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _Brand.maxWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_Brand.accent, _Brand.accentBright],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Text('E',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                  ),
                  const SizedBox(width: 12),
                  const Text('Esep',
                      style: TextStyle(
                          fontSize: 18, color: _Brand.text,
                          fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _Brand.tagBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('PARTNER',
                        style: TextStyle(
                            fontSize: 10, color: _Brand.accent,
                            fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                  ),
                  const SizedBox(width: 28),
                  const Text('Партнёрский кабинет',
                      style: TextStyle(
                          color: _Brand.textSecondary, fontSize: 14, fontWeight: FontWeight.w500)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Iconsax.refresh, color: _Brand.text, size: 18),
                    onPressed: _load,
                    tooltip: 'Обновить',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _Brand.orange.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Iconsax.info_circle, size: 34, color: _Brand.orange),
            ),
            const SizedBox(height: 20),
            const Text(
              'Партнёрский статус ещё не активирован',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _Brand.text),
            ),
            const SizedBox(height: 10),
            const Text(
              'Напишите фаундеру Esep в WhatsApp +7 707 588 46 51 — оформим в течение часа.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _Brand.textSecondary, height: 1.45),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _Brand.accent, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _load,
              child: const Text('Проверить ещё раз'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final stats = (_data?['stats'] as Map?) ?? {};
    final partner = (_data?['partner'] as Map?) ?? {};
    final promos = (_data?['promos'] as List?) ?? [];
    final activations = (_data?['recent_activations'] as List?) ?? [];

    return RefreshIndicator(
      color: _Brand.accent,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _Brand.maxWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildEarningsHero(stats, partner),
                  const SizedBox(height: 28),
                  _sectionHeader(
                    tag: 'Ваши промокоды',
                    title: 'Раздавайте клиентам — получайте % с подписки',
                    sub: 'Каждая активация = пассивный доход каждый месяц пока клиент платит',
                  ),
                  const SizedBox(height: 18),
                  _buildPromosList(promos),
                  const SizedBox(height: 32),
                  _sectionHeader(
                    tag: 'Активации',
                    title: 'Последние подключения клиентов',
                    sub: 'Кто активировал ваш код за последнее время',
                  ),
                  const SizedBox(height: 18),
                  _buildActivationsList(activations),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader({required String tag, required String title, required String sub}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: _Brand.tagBg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            tag.toUpperCase(),
            style: const TextStyle(
              color: _Brand.accent, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 0.7,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(title,
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800,
                color: _Brand.text, letterSpacing: -0.5, height: 1.15)),
        const SizedBox(height: 4),
        Text(sub,
            style: const TextStyle(
                fontSize: 14, color: _Brand.textSecondary, height: 1.45)),
      ],
    );
  }

  // ─── EARNINGS HERO ────────────────────────────────────────────────────────
  Widget _buildEarningsHero(Map stats, Map partner) {
    final earnedMonth = (stats['earned_this_month'] as num?)?.toInt() ?? 0;
    final earnedTotal = (stats['earned_total'] as num?)?.toInt() ?? 0;
    final activeClients = (stats['active_clients'] as num?)?.toInt() ?? 0;
    final totalActivations = (stats['total_activations'] as num?)?.toInt() ?? 0;
    final companyName = (partner['company_name'] as String?)?.trim();
    final pct = (partner['commission_pct'] as num?)?.toInt() ?? 30;

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_Brand.bgDark, _Brand.cardDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _Brand.bgDark.withValues(alpha: 0.18),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _Brand.green.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'ПАРТНЁР ESEP · $pct%',
                  style: const TextStyle(
                      color: _Brand.greenBright, fontSize: 10.5,
                      fontWeight: FontWeight.w800, letterSpacing: 0.9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            companyName?.isNotEmpty == true ? companyName! : 'Партнёрский кабинет',
            style: const TextStyle(
                color: _Brand.textOnDark, fontSize: 30,
                fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.1),
          ),
          const SizedBox(height: 6),
          Text(
            'Вы зарабатываете $pct% с каждой подписки клиента',
            style: const TextStyle(color: _Brand.textDim, fontSize: 14),
          ),
          const SizedBox(height: 28),
          LayoutBuilder(builder: (ctx, c) {
            final cols = c.maxWidth >= 800 ? 4 : c.maxWidth >= 480 ? 2 : 1;
            final items = [
              _StatTile(
                label: 'Заработано в этом месяце',
                value: '${_fmtMoney(earnedMonth)} ₸',
                hint: 'обновляется ежедневно',
                icon: Iconsax.dollar_circle,
                color: _Brand.greenBright,
              ),
              _StatTile(
                label: 'Заработано всего',
                value: '${_fmtMoney(earnedTotal)} ₸',
                hint: 'с момента старта',
                icon: Iconsax.wallet_2,
                color: _Brand.accentBright,
              ),
              _StatTile(
                label: 'Активных клиентов',
                value: '$activeClients',
                hint: 'платящих подписку',
                icon: Iconsax.user_octagon,
                color: const Color(0xFFFACC15),
              ),
              _StatTile(
                label: 'Всего активаций',
                value: '$totalActivations',
                hint: 'с начала программы',
                icon: Iconsax.tick_circle,
                color: _Brand.greenBright,
              ),
            ];
            return _gridOfTiles(items, cols);
          }),
        ],
      ),
    );
  }

  Widget _gridOfTiles(List<_StatTile> items, int cols) {
    final rows = <Widget>[];
    for (int i = 0; i < items.length; i += cols) {
      final children = <Widget>[];
      for (int j = 0; j < cols; j++) {
        if (i + j < items.length) {
          children.add(Expanded(child: _statTileWidget(items[i + j])));
          if (j < cols - 1 && i + j + 1 < items.length) {
            children.add(const SizedBox(width: 14));
          }
        } else {
          children.add(const Expanded(child: SizedBox.shrink()));
        }
      }
      rows.add(Row(children: children));
      if (i + cols < items.length) rows.add(const SizedBox(height: 14));
    }
    return Column(children: rows);
  }

  Widget _statTileWidget(_StatTile s) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _Brand.cardDarkAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Brand.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: s.color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(s.icon, color: s.color, size: 17),
          ),
          const SizedBox(height: 14),
          Text(s.value,
              style: const TextStyle(
                  color: _Brand.textOnDark, fontSize: 24,
                  fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.0)),
          const SizedBox(height: 6),
          Text(s.label,
              style: const TextStyle(color: _Brand.textDim, fontSize: 12)),
          const SizedBox(height: 2),
          Text(s.hint,
              style: const TextStyle(
                  color: _Brand.textDim, fontSize: 10.5, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  // ─── PROMOS ────────────────────────────────────────────────────────────────
  Widget _buildPromosList(List promos) {
    return Container(
      decoration: BoxDecoration(
        color: _Brand.cardLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Brand.border),
      ),
      child: Column(
        children: [
          if (promos.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  const Icon(Iconsax.ticket, size: 36, color: _Brand.textSecondary),
                  const SizedBox(height: 12),
                  const Text(
                    'У вас пока нет промокодов',
                    style: TextStyle(
                        fontSize: 15, color: _Brand.text, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Создайте первый — раздайте клиентам и зарабатывайте',
                    style: TextStyle(fontSize: 13, color: _Brand.textSecondary),
                  ),
                ],
              ),
            )
          else
            ...promos.map((p) => _promoRow(Map<String, dynamic>.from(p as Map))),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _Brand.border)),
            ),
            child: ListTile(
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: _Brand.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Iconsax.add_circle, color: _Brand.accent, size: 20),
              ),
              title: const Text('Создать новый промокод',
                  style: TextStyle(
                      fontSize: 14.5, color: _Brand.accent, fontWeight: FontWeight.w700)),
              subtitle: const Text(
                'Сгенерируем уникальный код с вашей префиксом',
                style: TextStyle(fontSize: 12, color: _Brand.textSecondary),
              ),
              onTap: _generatePromo,
            ),
          ),
        ],
      ),
    );
  }

  Widget _promoRow(Map<String, dynamic> p) {
    final code = (p['code'] ?? '').toString();
    final tier = (p['grant_tier'] ?? 'solo').toString();
    final activations = (p['activations'] as num?)?.toInt() ?? 0;
    final duration = (p['duration_days'] as num?)?.toInt() ?? 30;
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _Brand.border)),
      ),
      child: ListTile(
        leading: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: _Brand.tagBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Iconsax.ticket, color: _Brand.accent, size: 18),
        ),
        title: Row(
          children: [
            SelectableText(
              code,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _Brand.text,
                fontFamily: 'monospace',
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _Brand.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                tier.toUpperCase(),
                style: const TextStyle(
                  fontSize: 9.5,
                  color: _Brand.green,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          '$activations активаций · $duration дней бесплатно',
          style: const TextStyle(fontSize: 12.5, color: _Brand.textSecondary),
        ),
        trailing: IconButton(
          icon: const Icon(Iconsax.copy, size: 18),
          color: _Brand.accent,
          tooltip: 'Скопировать',
          onPressed: () => _copyCode(code),
        ),
      ),
    );
  }

  // ─── ACTIVATIONS ──────────────────────────────────────────────────────────
  Widget _buildActivationsList(List activations) {
    if (activations.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: _Brand.cardLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _Brand.border),
        ),
        child: Column(
          children: const [
            Icon(Iconsax.user_add, size: 36, color: _Brand.textSecondary),
            SizedBox(height: 12),
            Text('Пока нет активаций',
                style: TextStyle(
                    fontSize: 15, color: _Brand.text, fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text('Когда клиенты введут ваш промокод — они появятся здесь',
                style: TextStyle(fontSize: 13, color: _Brand.textSecondary)),
          ],
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: _Brand.cardLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _Brand.border),
      ),
      child: Column(
        children: activations
            .map((a) => _activationRow(Map<String, dynamic>.from(a as Map)))
            .toList(),
      ),
    );
  }

  Widget _activationRow(Map<String, dynamic> a) {
    final email = (a['client_email'] ?? '—').toString();
    final code = (a['code'] ?? '').toString();
    final commission = (a['monthly_commission'] as num?)?.toInt() ?? 0;
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _Brand.border)),
      ),
      child: ListTile(
        leading: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: _Brand.green.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Iconsax.user, color: _Brand.green, size: 16),
        ),
        title: Text(email,
            style: const TextStyle(
                fontSize: 13.5, color: _Brand.text, fontWeight: FontWeight.w600)),
        subtitle: Text('код $code',
            style: const TextStyle(
                fontSize: 11.5, color: _Brand.textSecondary, fontFamily: 'monospace')),
        trailing: Text(
          '+${_fmtMoney(commission)} ₸/мес',
          style: const TextStyle(
              color: _Brand.green, fontSize: 13.5, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  String _fmtMoney(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      buf.write(s[i]);
      count++;
      if (count == 3 && i > 0) {
        buf.write(' ');
        count = 0;
      }
    }
    return buf.toString().split('').reversed.join();
  }
}

class _StatTile {
  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color color;
  const _StatTile({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.color,
  });
}
