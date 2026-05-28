import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/services/auth_service.dart';

/// Красный баннер сверху, показывается когда админ вошёл под клиента
/// (JWT содержит claim `imp: true`). Клик «Выйти» — logout.
class ImpersonationBanner extends ConsumerStatefulWidget {
  const ImpersonationBanner({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ImpersonationBanner> createState() =>
      _ImpersonationBannerState();
}

class _ImpersonationBannerState extends ConsumerState<ImpersonationBanner> {
  bool _isImp = false;
  String? _email;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final isImp = await AuthService.isImpersonated();
    final email = await AuthService.getEmail();
    if (!mounted) return;
    setState(() {
      _isImp = isImp;
      _email = email;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Перечитываем при изменении состояния авторизации
    ref.listen(authProvider, (_, __) => _check());

    if (!_isImp) return widget.child;

    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: const Color(0xFF7C3AED),
              child: Row(
                children: [
                  const Icon(Icons.visibility, color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Режим админа: вы вошли как ${_email ?? "клиент"}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ref.read(authProvider.notifier).logout();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('Выйти'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}
