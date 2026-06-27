import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models.dart';
import 'screens/diary_screen.dart';
import 'screens/food_detail_screen.dart';
import 'screens/goal_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/search_screen.dart';

void main() => runApp(const ProviderScope(child: SitosApp()));

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const DiaryScreen()),
    GoRoute(path: '/scan', builder: (_, _) => const ScanScreen()),
    GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
    GoRoute(path: '/goal', builder: (_, _) => const GoalScreen()),
    GoRoute(
      path: '/food',
      builder: (_, state) => FoodDetailScreen(food: state.extra as Food),
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
