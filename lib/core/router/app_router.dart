import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/screens/auth_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/invoices/screens/invoices_screen.dart';
import '../../features/invoices/screens/invoice_detail_screen.dart';
import '../../features/transactions/screens/transactions_screen.dart';
import '../../features/taxes/screens/taxes_screen.dart';
import '../../features/clients/screens/clients_screen.dart';
import '../../shared/widgets/main_scaffold.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/dashboard',
    // TODO: redirect to /auth if not logged in
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
        ],
      ),
    ],
  );
});
