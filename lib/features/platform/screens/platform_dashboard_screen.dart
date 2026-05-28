/// Platform API Dashboard — корпоративный кабинет для enterprise-клиентов.
///
/// Дизайн в одной языке с лендингом business.esepkz.com:
///   • dark navy hero + light content sections
///   • section tags (pill style) над каждым разделом
///   • premium spacing rhythm (8 / 12 / 16 / 24 / 40px)
///   • cards с цветным иконкой-плашкой как на landing
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/services/platform_api_service.dart';
import '../widgets/service_card.dart';
import 'service_test_screen.dart' show ServiceTestScreen;

// ─── Design tokens — синхронизированы с client-demo/style.css ───────────────
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
  static const Color red          = Color(0xFFEF4444);
  static const Color tagBg        = Color(0xFFEBF1FF); // rgba(30,91,255,0.10) baked

  static const double maxWidth = 1280.0;
}

class PlatformDashboardScreen extends ConsumerStatefulWidget {
  const PlatformDashboardScreen({super.key});

  @override
  ConsumerState<PlatformDashboardScreen> createState() =>
      _PlatformDashboardScreenState();
}

class _PlatformDashboardScreenState
    extends ConsumerState<PlatformDashboardScreen> {
  PlatformAccount? _account;
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
      final acc = await PlatformApiService.myAccount();
      setState(() {
        _account = acc;
        _loading = false;
        if (acc == null) {
          _error = 'У вашего аккаунта нет доступа к Platform API.';
        }
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Ошибка загрузки данных: $e';
      });
    }
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

  // ─── TOP BAR ──────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: _Brand.border, width: 1),
        ),
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
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: _Brand.accent.withValues(alpha: 0.30),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'E',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 17,
                        color: _Brand.text,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                      children: [
                        TextSpan(text: 'esep'),
                        TextSpan(
                          text: 'platform',
                          style: TextStyle(
                            color: _Brand.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 28),
                  const Text(
                    'Корпоративный кабинет',
                    style: TextStyle(
                      color: _Brand.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  _navButton('Документация', null, false),
                  const SizedBox(width: 6),
                  _navButton('Поддержка', null, false),
                  const SizedBox(width: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: _Brand.bgPage,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Iconsax.refresh, color: _Brand.text, size: 18),
                      onPressed: _load,
                      tooltip: 'Обновить',
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navButton(String label, IconData? icon, bool primary) {
    return TextButton(
      onPressed: () {},
      style: TextButton.styleFrom(
        foregroundColor: primary ? Colors.white : _Brand.textSecondary,
        backgroundColor: primary ? _Brand.accent : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label),
    );
  }

  // ─── ERROR STATE ──────────────────────────────────────────────────────────
  Widget _buildError() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
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
                child: const Icon(
                  Iconsax.info_circle,
                  size: 34,
                  color: _Brand.orange,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                _error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: _Brand.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 26),
              _primaryButton(label: 'Повторить', onPressed: _load),
            ],
          ),
        ),
      ),
    );
  }

  // ─── CONTENT ──────────────────────────────────────────────────────────────
  Widget _buildContent() {
    final acc = _account!;
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
                  _buildHero(acc),
                  const SizedBox(height: 32),
                  _sectionHeader(
                    tag: 'Сервисы',
                    title: 'Подключённые возможности',
                    sub: 'Кликни по карточке — попробуй вживую через реальный API',
                  ),
                  const SizedBox(height: 18),
                  _buildServicesGrid(acc),
                  const SizedBox(height: 40),
                  _sectionHeader(
                    tag: 'Интеграция',
                    title: 'Подключение за 14 дней',
                    sub: 'Один HTTP-запрос вместо девяти сторонних интеграций',
                  ),
                  const SizedBox(height: 18),
                  _buildIntegrationCard(acc),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── SECTION HEADER (как на лендинге) ─────────────────────────────────────
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
              color: _Brand.accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: _Brand.text,
            letterSpacing: -0.6,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          sub,
          style: const TextStyle(
            fontSize: 14.5,
            color: _Brand.textSecondary,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  // ─── HERO (полностраничный hero с stats внутри) ───────────────────────────
  Widget _buildHero(PlatformAccount acc) {
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top block — info + key chip
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 32, 36, 28),
            child: LayoutBuilder(builder: (ctx, c) {
              final wide = c.maxWidth >= 760;
              final leftBlock = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _Brand.green.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'ENTERPRISE · PLATFORM API',
                      style: TextStyle(
                        color: _Brand.greenBright,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    acc.clientName,
                    style: const TextStyle(
                      color: _Brand.textOnDark,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      height: 1.1,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    acc.clientBin != null
                        ? 'БИН ${acc.clientBin} · Compliance под Закон 214-VIII'
                        : 'Compliance под Закон 214-VIII',
                    style: const TextStyle(
                      color: _Brand.textDim,
                      fontSize: 14,
                    ),
                  ),
                ],
              );
              final rightBlock = _buildApiKeyCard(acc);

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: leftBlock),
                    const SizedBox(width: 32),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: rightBlock,
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  leftBlock,
                  const SizedBox(height: 22),
                  rightBlock,
                ],
              );
            }),
          ),
          // Divider
          Container(
            height: 1,
            color: _Brand.borderDark.withValues(alpha: 0.6),
          ),
          // Stats row внутри hero
          _buildHeroStats(acc),
        ],
      ),
    );
  }

  Widget _buildApiKeyCard(PlatformAccount acc) {
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
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _Brand.accent.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(Iconsax.key, color: _Brand.accentBright, size: 15),
              ),
              const SizedBox(width: 10),
              const Text(
                'API Key',
                style: TextStyle(
                  color: _Brand.textOnDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              const Spacer(),
              const Text(
                'live',
                style: TextStyle(
                  color: _Brand.greenBright,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SelectableText(
            _maskKey(acc.apiKey),
            style: const TextStyle(
              color: _Brand.textOnDark,
              fontSize: 14,
              fontFamily: 'monospace',
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Используй заголовок\nX-Platform-Key: <ключ>',
            style: const TextStyle(
              color: _Brand.textDim,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  String _maskKey(String key) {
    if (key.length < 16) return key;
    return '${key.substring(0, 10)}····${key.substring(key.length - 6)}';
  }

  Widget _buildHeroStats(PlatformAccount acc) {
    final usagePercent = acc.monthlyQuota > 0
        ? (acc.requestsThisMonth / acc.monthlyQuota * 100).clamp(0, 100).toStringAsFixed(1)
        : '∞';
    final items = [
      _HeroStat(
        label: 'Запросов в этом месяце',
        value: '${acc.requestsThisMonth}',
        hint: acc.monthlyQuota > 0
            ? 'из ${acc.monthlyQuota} ($usagePercent%)'
            : 'безлимит',
        icon: Iconsax.activity,
        color: _Brand.accentBright,
      ),
      _HeroStat(
        label: 'Фискализировано чеков',
        value: '${acc.receipts.issued}',
        hint: 'из ${acc.receipts.total} операций',
        icon: Iconsax.tick_circle,
        color: _Brand.greenBright,
      ),
      _HeroStat(
        label: 'Сумма выплат',
        value: '${_formatMoney(acc.receipts.totalAmount)} ₸',
        hint: 'через Webkassa → КГД',
        icon: Iconsax.money,
        color: const Color(0xFFFACC15),
      ),
      _HeroStat(
        label: 'Время отклика',
        value: '< 200 мс',
        hint: 'SLA 99.9%',
        icon: Iconsax.flash_1,
        color: _Brand.accentBright,
      ),
    ];

    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth >= 900 ? 4 : c.maxWidth >= 560 ? 2 : 1;
      final rows = <Widget>[];
      for (int i = 0; i < items.length; i += cols) {
        final rowChildren = <Widget>[];
        for (int j = 0; j < cols; j++) {
          if (i + j < items.length) {
            rowChildren.add(Expanded(child: _heroStatCell(items[i + j])));
            if (j < cols - 1 && i + j + 1 < items.length) {
              rowChildren.add(_heroStatDivider());
            }
          } else {
            rowChildren.add(const Expanded(child: SizedBox.shrink()));
          }
        }
        rows.add(IntrinsicHeight(child: Row(children: rowChildren)));
        if (i + cols < items.length) {
          rows.add(Container(height: 1, color: _Brand.borderDark.withValues(alpha: 0.6)));
        }
      }
      return Column(children: rows);
    });
  }

  Widget _heroStatDivider() => Container(
        width: 1,
        color: _Brand.borderDark.withValues(alpha: 0.6),
      );

  Widget _heroStatCell(_HeroStat s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: s.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(s.icon, color: s.color, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  s.label,
                  style: const TextStyle(
                    color: _Brand.textDim,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  s.value,
                  style: const TextStyle(
                    color: _Brand.textOnDark,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s.hint,
                  style: const TextStyle(
                    color: _Brand.textDim,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── SERVICES GRID ────────────────────────────────────────────────────────
  Widget _buildServicesGrid(PlatformAccount acc) {
    final services = _buildServices(acc);
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth;
      final cols = w >= 1180 ? 4 : w >= 880 ? 3 : w >= 560 ? 2 : 1;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 160,
        ),
        itemCount: services.length,
        itemBuilder: (_, i) {
          final s = services[i];
          return ServiceCard(
            number: s.number,
            title: s.title,
            subtitle: s.subtitle,
            icon: s.icon,
            status: s.status,
            enabled: s.enabled,
            onTap: s.enabled
                ? () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ServiceTestScreen(
                        serviceCode: s.code,
                        title: s.title,
                        apiKey: acc.apiKey,
                      ),
                    ))
                : null,
          );
        },
      );
    });
  }

  // ─── INTEGRATION CARD ─────────────────────────────────────────────────────
  Widget _buildIntegrationCard(PlatformAccount acc) {
    return Container(
      decoration: BoxDecoration(
        color: _Brand.bgDark,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _Brand.bgDark.withValues(alpha: 0.20),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: LayoutBuilder(builder: (ctx, c) {
        final wide = c.maxWidth >= 880;
        final leftBlock = Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _Brand.accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Iconsax.code, color: _Brand.accentBright, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Параметры подключения',
                    style: TextStyle(
                      color: _Brand.textOnDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _kvRow('API URL', acc.apiBaseUrl),
              const SizedBox(height: 10),
              _kvRow('Заголовок авторизации', 'X-Platform-Key: <ключ>'),
              const SizedBox(height: 10),
              _kvRow('Главный endpoint', 'POST /process-payment'),
            ],
          ),
        );

        final rightBlock = Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _Brand.cardDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _Brand.borderDark),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Один запрос = весь compliance',
                style: TextStyle(
                  color: _Brand.textOnDark,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              for (final step in const [
                '1. Валидация ИИН курьера',
                '2. Проверка СНР / ОКЭД',
                '3. Контроль лимита 300 МРП',
                '4. Фискализация через Webkassa',
                '5. Регистрация чека в КГД',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: _Brand.accentBright,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          step,
                          style: const TextStyle(
                            color: _Brand.textDim,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: leftBlock),
              Expanded(flex: 2, child: rightBlock),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [leftBlock, rightBlock],
        );
      }),
    );
  }

  Widget _kvRow(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 180,
          child: Text(
            k,
            style: const TextStyle(
              fontSize: 12.5,
              color: _Brand.textDim,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            v,
            style: const TextStyle(
              fontSize: 13.5,
              fontFamily: 'monospace',
              color: _Brand.textOnDark,
            ),
          ),
        ),
      ],
    );
  }

  // ─── HELPERS ──────────────────────────────────────────────────────────────
  Widget _primaryButton({required String label, required VoidCallback onPressed}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: _Brand.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }

  String _formatMoney(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  List<_ServiceDef> _buildServices(PlatformAccount acc) {
    return [
      _ServiceDef(
        number: 1,
        code: 'process_payment',
        title: 'Magic — выплата курьеру',
        subtitle: 'Один вызов: проверка + фискализация',
        icon: Iconsax.flash_15,
        status: ServiceStatus.live,
        enabled: acc.hasFeature('process_payment'),
      ),
      _ServiceDef(
        number: 2,
        code: 'taxpayer_info',
        title: 'СНР и ОКЭД',
        subtitle: 'Проверка по БИН/ИИН через stat.gov.kz',
        icon: Iconsax.search_normal,
        status: ServiceStatus.live,
        enabled: acc.hasFeature('taxpayer_info'),
      ),
      _ServiceDef(
        number: 3,
        code: 'taxpayer_info',
        title: 'Статус ИП / ФЛ / ТОО',
        subtitle: 'Тип юр.формы из реестра',
        icon: Iconsax.profile_2user,
        status: ServiceStatus.live,
        enabled: acc.hasFeature('taxpayer_info'),
      ),
      _ServiceDef(
        number: 4,
        code: 'iin_validate',
        title: 'Валидация ИИН',
        subtitle: 'Алгоритмическая проверка контрольной цифры',
        icon: Iconsax.shield_tick,
        status: ServiceStatus.live,
        enabled: acc.hasFeature('iin_validate'),
      ),
      _ServiceDef(
        number: 5,
        code: 'cancel_order',
        title: 'Аннулирование чека',
        subtitle: 'Soft cancel заказа до фискализации',
        icon: Iconsax.close_circle,
        status: ServiceStatus.live,
        enabled: acc.hasFeature('cancel_receipt'),
      ),
      _ServiceDef(
        number: 6,
        code: 'receipt_status',
        title: 'Статус чека',
        subtitle: 'Фискальный № + QR от КГД',
        icon: Iconsax.receipt,
        status: ServiceStatus.live,
        enabled: acc.hasFeature('receipt_status'),
      ),
      _ServiceDef(
        number: 7,
        code: 'income_limit',
        title: 'Лимит 300 МРП',
        subtitle: 'Учёт месячного дохода самозанятого',
        icon: Iconsax.chart_2,
        status: ServiceStatus.live,
        enabled: acc.hasFeature('income_limit'),
      ),
      _ServiceDef(
        number: 8,
        code: 'self_employed_registry',
        title: 'Реестр самозанятых',
        subtitle: 'Источник: КГД ИСНА (договор оформляется)',
        icon: Iconsax.people,
        status: ServiceStatus.demo,
        enabled: acc.hasFeature('self_employed_registry'),
      ),
      _ServiceDef(
        number: 9,
        code: 'benefits',
        title: 'Льготы самозанятых',
        subtitle: 'Молодёжь / многодетные / инвалиды',
        icon: Iconsax.heart,
        status: ServiceStatus.demo,
        enabled: acc.hasFeature('benefits'),
      ),
    ];
  }
}

class _ServiceDef {
  final int number;
  final String code;
  final String title;
  final String subtitle;
  final IconData icon;
  final ServiceStatus status;
  final bool enabled;

  _ServiceDef({
    required this.number,
    required this.code,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.status,
    required this.enabled,
  });
}

class _HeroStat {
  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color color;
  const _HeroStat({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.color,
  });
}
