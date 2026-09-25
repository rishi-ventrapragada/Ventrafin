import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/providers.dart';
import 'features/auth/login_screen.dart';
import 'features/bills/bill_form_screen.dart';
import 'features/bills/bills_screen.dart';
import 'features/categories/categories_screen.dart';
import 'features/entry/add_screen.dart';
import 'features/entry/edit_transaction_screen.dart';
import 'features/lock/lock_controller.dart';
import 'features/lock/setup_lock_screen.dart';
import 'features/reports/reports_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/shell/simple_screens.dart';
import 'features/transactions/transactions_screen.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Routes (one per section, DECISIONS.md D8):
///   /login, /setup-lock, /splash
///   /dashboard  /transactions (/transactions/:id)  /add  /bills (/bills/new, /bills/:id)
///   /more (/more/categories, /more/accounts, /more/reports, /more/settings)
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/dashboard',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final signedIn = ref.read(currentUserIdProvider) != null;
      if (!signedIn) return loc == '/login' ? null : '/login';

      final hasPattern = ref.read(hasPatternProvider);
      if (!hasPattern.hasValue && !hasPattern.hasError) return loc == '/splash' ? null : '/splash';
      if (hasPattern.value != true) return loc == '/setup-lock' ? null : '/setup-lock';

      if (loc == '/login' || loc == '/setup-lock' || loc == '/splash') return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/splash', builder: (_, _) => const Scaffold(body: Center(child: CircularProgressIndicator()))),
      GoRoute(path: '/setup-lock', builder: (_, _) => const SetupLockScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/transactions',
              builder: (_, _) => const TransactionsScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  parentNavigatorKey: _rootKey,
                  builder: (_, state) => EditTransactionScreen(id: state.pathParameters['id']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/add', builder: (_, _) => const AddScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/bills',
              builder: (_, _) => const BillsScreen(),
              routes: [
                GoRoute(path: 'new', parentNavigatorKey: _rootKey, builder: (_, _) => const BillFormScreen()),
                GoRoute(
                  path: ':id',
                  parentNavigatorKey: _rootKey,
                  builder: (_, state) => BillFormScreen(billId: state.pathParameters['id']),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/more',
              builder: (_, _) => const MoreScreen(),
              routes: [
                GoRoute(path: 'categories', builder: (_, _) => const CategoriesScreen()),
                GoRoute(path: 'accounts', builder: (_, _) => const AccountsScreen()),
                GoRoute(path: 'reports', builder: (_, _) => const ReportsScreen()),
                GoRoute(
                  path: 'settings',
                  builder: (_, _) => const SettingsScreen(),
                  routes: [
                    GoRoute(
                      path: 'change-pattern',
                      parentNavigatorKey: _rootKey,
                      builder: (context, _) => SetupLockScreen(
                        requireCurrent: true,
                        onDone: () {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Unlock pattern changed')));
                          context.pop();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
});

/// Re-runs the router's redirect when sign-in state or pattern setup changes.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(currentUserIdProvider, (_, _) => notifyListeners());
    ref.listen(hasPatternProvider, (_, _) => notifyListeners());
  }
}
