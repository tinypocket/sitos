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
import 'screens/recipe_editor_screen.dart';
import 'screens/recipes_screen.dart';
import 'screens/review_confirm_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/smart_add_screen.dart';
import 'screens/splash_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: SitosApp()));
  // Initialize Google sign-in in the background — never block the first frame on it.
  // The router reacts to auth changes via refreshListenable.
  unawaited(AuthService.instance.ensureInitialized());
}

final _router = GoRouter(
  // Re-evaluate redirects whenever the auth gate state changes (restoring → signed in/out).
  refreshListenable: AuthService.instance.status,
  redirect: (context, state) {
    if (!AuthService.enabled) return null; // login gate off in dev (no client id)
    final status = AuthService.instance.status.value;
    final loc = state.matchedLocation;
    // Still checking for a saved session — show the splash, never the login screen.
    if (status == AuthStatus.unknown) return loc == '/splash' ? null : '/splash';
    if (status == AuthStatus.signedOut) return loc == '/login' ? null : '/login';
    // Signed in: bounce off the splash/login screens into the app.
    if (loc == '/login' || loc == '/splash') return '/';
    return null;
  },
  routes: [
    GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
    GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    GoRoute(path: '/', builder: (_, _) => const DiaryScreen()),
    GoRoute(path: '/scan', builder: (_, _) => const ScanScreen()),
    GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
    GoRoute(path: '/goal', builder: (_, _) => const GoalScreen()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    GoRoute(path: '/recipes', builder: (_, _) => const RecipesScreen()),
    GoRoute(
      path: '/recipe/edit',
      // Optional existing recipe passed via extra (null = create new).
      builder: (_, state) => RecipeEditorScreen(recipe: state.extra as Recipe?),
    ),
    GoRoute(
      path: '/food',
      builder: (_, state) => FoodDetailScreen(food: state.extra as Food),
    ),
    GoRoute(
      path: '/food/new',
      // Optional prefilled barcode passed via extra (from a failed scan).
      builder: (_, state) => AddFoodScreen(initialBarcode: state.extra as String?),
    ),
    // Entry experience (E3 → E2).
    GoRoute(
      path: '/add/smart',
      builder: (_, state) => SmartAddScreen(meal: state.extra as Meal?),
    ),
    GoRoute(path: '/add/review', builder: (_, _) => const ReviewConfirmScreen()),
  ],
);

class SitosApp extends StatelessWidget {
  const SitosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Sitos',
      debugShowCheckedModeBanner: false,
      theme: sitosTheme(),
      routerConfig: _router,
    );
  }
}
