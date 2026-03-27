import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/shell/presentation/app_shell.dart';
import '../features/notifications/presentation/notifications_page.dart';
import '../features/rentals/presentation/rental_details_page.dart';
import '../features/listings/presentation/rental_alerts_page.dart';
import '../features/lost_id/presentation/lost_id_details_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const AppShell(),
        routes: [
          GoRoute(
            path: 'notifications',
            builder: (context, state) => const NotificationsPage(),
          ),
          GoRoute(
            path: 'rental/:id',
            builder: (context, state) =>
                RentalDetailsPage(id: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'rental-alerts',
            builder: (context, state) => const RentalAlertsPage(),
          ),
          GoRoute(
            path: 'lost-id/:id',
            builder: (context, state) =>
                LostIdDetailsPage(id: state.pathParameters['id']!),
          ),
        ],
      ),
    ],
  );
});
