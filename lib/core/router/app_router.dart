import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/screens/auth_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/invoices/screens/invoices_screen.dart';
import '../../features/invoices/screens/invoice_detail_screen.dart';
import '../../features/transactions/screens/transactions_screen.dart';
import '../../features/taxes/screens/taxes_screen.dart';
import '../../features/clients/screens/clients_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../shared/widgets/main_scaffold.dart';
import '../providers/auth_provider.dart';

// Bridge between Riverpod and GoRouter's refreshListenable
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
  }
}

final _authListenableProvider =
    ChangeNotifierProvider((ref) => _AuthListenable(ref));

final appRouterProvider = Provider<GoRouter>((ref) {
  final listenable = ref.watch(_authListenableProvider);

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: listenable,
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final goingToAuth = state.matchedLocation == '/auth';

      if (authState == AuthState.loading) return null;

      if (authState == AuthState.unauthenticated && !goingToAuth) {
        return '/auth';
      }
      if (authState == AuthState.authenticated && goingToAuth) {
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth',
        builder: (_, __) => const AuthScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
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
            path: '/clients',
            builder: (_, __) => const ClientsScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});
