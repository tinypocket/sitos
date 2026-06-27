import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_service.dart';
import 'models.dart';
import 'screens/add_food_screen.dart';
import 'screens/diary_screen.dart';
import 'screens/food_detail_screen.dart';
import 'screens/goal_screen.dart';
import 'screens/login_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/search_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: SitosApp()));
  // Initialize Google sign-in in the background — never block the first frame on it.
  // The router reacts to auth changes via refreshListenable.
  unawaited(AuthService.instance.ensureInitialized());
}

final _router = GoRouter(
  // Re-evaluate redirects whenever the signed-in account changes.
  refreshListenable: AuthService.instance.account,
  redirect: (context, state) {
    if (!AuthService.enabled) return null; // login gate off in dev (no client id)
    final signedIn = AuthService.instance.account.value != null;
    final atLogin = state.matchedLocation == '/login';
    if (!signedIn) return atLogin ? null : '/login';
    if (atLogin) return '/';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    GoRoute(path: '/', builder: (_, _) => const DiaryScreen()),
    GoRoute(path: '/scan', builder: (_, _) => const ScanScreen()),
    GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
    GoRoute(path: '/goal', builder: (_, _) => const GoalScreen()),
    GoRoute(
      path: '/food',
      builder: (_, state) => FoodDetailScreen(food: state.extra as Food),
    ),
    GoRoute(
      path: '/food/new',
      // Optional prefilled barcode passed via extra (from a failed scan).
      builder: (_, state) => AddFoodScreen(initialBarcode: state.extra as String?),
    ),
  ],
);

class SitosApp extends StatelessWidget {
  const SitosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Sitos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
