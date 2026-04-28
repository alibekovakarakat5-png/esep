import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';

/// Has the user seen onboarding?
final hasSeenOnboardingProvider = StateProvider<bool>((ref) {
  return Hive.box('settings').get('onboarding_done', defaultValue: false) as bool;
});

void _markOnboardingDone(WidgetRef ref) {
  Hive.box('settings').put('onboarding_done', true);
  ref.read(hasSeenOnboardingProvider.notifier).state = true;
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _PageData(
      icon: Iconsax.heart,
      color: EsepColors.primary,
      title: 'Добро пожаловать в Esep',
      subtitle: 'Мы поможем разобраться с налогами.\n'
          'Даже если вы в этом ничего не понимаете —\n'
          'это нормально.',
    ),
    _PageData(
      icon: Iconsax.arrow_right_3,
      color: Color(0xFF7B2FBE),
      title: 'Как это работает',
      subtitle: 'Записывайте доходы\n'
          '-> Esep посчитает налоги\n'
          '-> Покажет сколько и когда платить',
    ),
    _PageData(
      icon: Iconsax.shield_tick,
      color: EsepColors.warning,
      title: 'Никаких штрафов',
      subtitle: 'Мы напомним о каждом платеже заранее.\n'
          'Вы точно ничего не пропустите.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _pages.length - 1) {
      _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _finish();
    }
  }

  void _finish() {
    _markOnboardingDone(ref);
    context.go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 720;

    final content = Column(
      children: [
        // Skip button
        Padding(
          padding: const EdgeInsets.only(top: 8, right: 12),
          child: Align(
            alignment: Alignment.topRight,
            child: TextButton(
              onPressed: _finish,
              child: const Text('Пропустить',
                  style: TextStyle(color: EsepColors.textSecondary, fontSize: 14)),
            ),
          ),
        ),

        // Pages
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: _pages.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => _OnboardingPage(data: _pages[i]),
          ),
        ),

        // Dots
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_pages.length, (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == _page ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == _page ? EsepColors.primary : EsepColors.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            )),
          ),
        ),

        // Buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _next,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  _page < _pages.length - 1 ? 'Далее' : 'Начать',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (_page == _pages.length - 1) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Iconsax.eye, size: 18),
                  label: const Text('Посмотреть без входа'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: EsepColors.primary.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    _markOnboardingDone(ref);
                    ref.read(authProvider.notifier).enterDemo();
                  },
                ),
              ),
            ],
          ]),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: isWide ? const Color(0xFFF5F6FA) : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWide ? 480 : double.infinity,
              maxHeight: isWide ? 720 : double.infinity,
            ),
            child: isWide
                ? Container(
                    margin: const EdgeInsets.symmetric(vertical: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 32,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: content,
                  )
                : content,
          ),
        ),
      ),
    );
  }
}

// ── Page data & widget ──────────────────────────────────────────────────────

class _PageData {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _PageData({required this.icon, required this.color, required this.title, required this.subtitle});
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.data});
  final _PageData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(data.icon, color: data.color, size: 48),
          ),
          const SizedBox(height: 36),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: EsepColors.textPrimary),
          ),
          const SizedBox(height: 14),
          Text(
            data.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: EsepColors.textSecondary, height: 1.6),
          ),
        ],
      ),
    );
  }
}
