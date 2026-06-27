import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'models.dart';

final apiProvider = Provider<SitosApi>((ref) => SitosApi());

/// The day currently shown in the diary. Defaults to today (date-only).
class SelectedDate extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void set(DateTime date) => state = date;
}

final selectedDateProvider =
    NotifierProvider<SelectedDate, DateTime>(SelectedDate.new);

/// The diary for the selected day, with rolled-up totals and goal.
final diaryProvider = FutureProvider.autoDispose<DiaryDay>((ref) async {
  final api = ref.watch(apiProvider);
  final date = ref.watch(selectedDateProvider);
  return api.getDiary(date);
});

final goalProvider = FutureProvider.autoDispose<Goal?>((ref) async {
  return ref.watch(apiProvider).getGoal();
});

/// Recently logged foods for one-tap re-add. Refreshes whenever the diary changes.
final recentFoodsProvider = FutureProvider.autoDispose<List<Food>>((ref) async {
  ref.watch(diaryProvider); // recompute after a log/delete
  return ref.watch(apiProvider).getRecentFoods();
});

final recipesProvider = FutureProvider.autoDispose<List<Recipe>>((ref) async {
  return ref.watch(apiProvider).getRecipes();
});
