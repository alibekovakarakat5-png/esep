import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/screens/auth_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/invoices/screens/invoices_screen.dart';
import '../../features/invoices/screens/invoice_detail_screen.dart';
import '../../features/transactions/screens/transactions_screen.dart';
import '../../features/taxes/screens/taxes_screen.dart';
import '../../features/clients/screens/clients_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/accountant/screens/accountant_dashboard_screen.dart';
import '../../features/accountant/screens/accountant_client_detail_screen.dart';
import '../../features/accountant/screens/deadline_calendar_screen.dart';
import '../../features/accountant/screens/lpr_finder_screen.dart';
import '../../features/mode_select/screens/mode_select_screen.dart';
import '../../features/taxes/screens/salary_calculator_screen.dart';
import '../../features/taxes/screens/too_calculator_screen.dart';
import '../../features/taxes/screens/form910_screen.dart';
import '../../features/taxes/screens/employees_screen.dart';
import '../../features/legal/screens/legal_doc_screen.dart';
import '../constants/legal_docs.dart';
import '../../features/transactions/screens/receipt_scanner_screen.dart';
import '../../features/tools/screens/bin_lookup_screen.dart';
import '../../features/tools/screens/regime_guide_screen.dart';
import '../../features/transactions/screens/bank_connect_screen.dart';
import '../../features/ai_chat/screens/ai_chat_screen.dart';
import '../../features/esf_recon/screens/esf_recon_screen.dart';
import '../../features/esf_recon/screens/esf_recon_detail_screen.dart';
import '../../features/account_monitor/screens/account_monitor_screen.dart';
import '../../features/settings/screens/tax_profile_screen.dart';
import '../../shared/widgets/main_scaffold.dart';
import '../providers/auth_provider.dart';
import '../providers/user_mode_provider.dart';

// ── Router Listeneables ───────────────────────────────────────────────────────

class _RouterListenable extends ChangeNotifier {
  _RouterListenable(Ref ref) {
    ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
    ref.listen<UserMode?>(userModeProvider, (_, __) => notifyListeners());
    ref.listen<bool>(hasSeenOnboardingProvider, (_, __) => notifyListeners());
  }
}

final _routerListenableProvider =
    ChangeNotifierProvider((ref) => _RouterListenable(ref));

// ── Router ────────────────────────────────────────────────────────────────────

final appRouterProvider = Provider<GoRouter>((ref) {
  final listenable = ref.watch(_routerListenableProvider);

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: listenable,
    redirect: (context, state) {
      final authState     = ref.read(authProvider);
      final mode          = ref.read(userModeProvider);
      final seenOnboarding = ref.read(hasSeenOnboardingProvider);
      final location      = state.matchedLocation;

      if (authState == AuthState.loading) return null;

      // First launch → onboarding
      if (!seenOnboarding && location != '/onboarding') {
        return '/onboarding';
      }

      // Not logged in → go to auth (юридические доки доступны без входа)
      if (seenOnboarding &&
          authState == AuthState.unauthenticated &&
          location != '/auth' &&
          location != '/onboarding' &&
          !location.startsWith('/legal/')) {
        return '/auth';
      }

      // Logged in, on auth or onboarding → pick mode or home
      if (authState == AuthState.authenticated &&
          (location == '/auth' || location == '/onboarding')) {
        return mode == null
            ? '/mode-select'
            : _homeForMode(mode);
      }

      // Logged in, no mode selected → mode selection
      if (authState == AuthState.authenticated &&
          mode == null &&
          location != '/mode-select') {
        return '/mode-select';
      }

      return null;
    },
    routes: [
      // ── Onboarding ──────────────────────────────────────────────────────
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),

      // ── Auth ─────────────────────────────────────────────────────────────
      GoRoute(
        path: '/auth',
        builder: (_, __) => const AuthScreen(),
      ),

      // ── Mode select (outside of shell = no bottom nav) ───────────────────
      GoRoute(
        path: '/mode-select',
        builder: (_, __) => const ModeSelectScreen(),
      ),

      // ── Юридические документы (доступны и до входа) ──────────────────────
      GoRoute(
        path: '/legal/:slug',
        builder: (_, state) {
          final type = LegalDocType.fromSlug(state.pathParameters['slug'] ?? '')
              ?? LegalDocType.terms;
          return LegalDocScreen(type: type);
        },
      ),

      // ── Main shell (with bottom nav) ─────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [

          // ─ ИП routes ─────────────────────────────────────────────────────
          GoRoute(
            path: '/dashboard',
            builder: (_, __) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/invoices',
            builder: (_, __) => const InvoicesScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => InvoiceDetailScreen(
                  invoiceId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/transactions',
            builder: (_, __) => const TransactionsScreen(),
          ),
          GoRoute(
            path: '/taxes',
            builder: (_, __) => const TaxesScreen(),
          ),
          GoRoute(
            path: '/salary-calculator',
            builder: (_, __) => const SalaryCalculatorScreen(),
          ),
          GoRoute(
            path: '/too-calculator',
            builder: (_, __) => const TooCalculatorScreen(),
          ),
          GoRoute(
            path: '/bin-lookup',
            builder: (_, __) => const BinLookupScreen(),
          ),
          GoRoute(
            path: '/regime-guide',
            builder: (ctx, state) => const RegimeGuideScreen(),
          ),
          GoRoute(
            path: '/form-910',
            builder: (_, __) => const Form910Screen(),
          ),
          GoRoute(
            path: '/employees',
            builder: (_, __) => const EmployeesScreen(),
          ),
          GoRoute(
            path: '/receipt-scanner',
            builder: (_, __) => const ReceiptScannerScreen(),
          ),
          GoRoute(
            path: '/bank-connect',
            builder: (_, __) => const BankConnectScreen(),
          ),
          GoRoute(
            path: '/clients',
            builder: (_, __) => const ClientsScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/ai-chat',
            builder: (_, __) => const AiChatScreen(),
          ),

          // ─ ЭСФ-сверщик (для ТОО / Бухгалтера) ─────────────────────────────
          GoRoute(
            path: '/esf-recon',
            builder: (_, __) => const EsfReconScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => EsfReconDetailScreen(
                  sessionId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),

          // ─ Лицевой счёт ───────────────────────────────────────────────────
          GoRoute(
            path: '/account-monitor',
            builder: (_, __) => const AccountMonitorScreen(),
          ),

          // ─ Налоговый профиль ──────────────────────────────────────────────
          GoRoute(
            path: '/tax-profile',
            builder: (_, __) => const TaxProfileScreen(),
          ),

          // ─ Бухгалтер routes ───────────────────────────────────────────────
          GoRoute(
            path: '/accountant',
            builder: (_, __) => const AccountantDashboardScreen(),
            routes: [
              GoRoute(
                path: 'calendar',
                builder: (_, __) => const DeadlineCalendarScreen(),
              ),
              GoRoute(
                path: 'client/:id',
                builder: (_, state) => AccountantClientDetailScreen(
                  clientId: state.pathParameters['id']!,
                ),
              ),
              GoRoute(
                path: 'lpr',
                builder: (_, __) => const LprFinderScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

String _homeForMode(UserMode mode) =>
    mode == UserMode.accountant ? '/accountant' : '/dashboard';
