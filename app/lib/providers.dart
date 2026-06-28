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

// ===== Entry experience: the in-progress "add" session =====

enum AddSource { text, photo, scan, manual }

enum AddStatus { idle, parsing, ready, committing, error }

/// The in-progress add session shared across E2 (review), E3 (smart add) and
/// E6 (portion editor).
class AddSessionState {
  final List<ReviewRow> rows;
  final Meal meal;
  final AddSource source;
  final AddStatus status;
  final String? error;

  const AddSessionState({
    required this.rows,
    required this.meal,
    required this.source,
    required this.status,
    this.error,
  });

  AddSessionState copyWith({
    List<ReviewRow>? rows,
    Meal? meal,
    AddSource? source,
    AddStatus? status,
    String? error,
  }) =>
      AddSessionState(
        rows: rows ?? this.rows,
        meal: meal ?? this.meal,
        source: source ?? this.source,
        status: status ?? this.status,
        error: error,
      );

  Iterable<ReviewRow> get committable => rows.where((r) => r.resolved);
  int get committableCount => committable.length;
  // Everything that won't be logged (no-match, or any row without a usable match).
  int get excludedCount => rows.length - committableCount;
  double get committableKcal =>
      committable.fold(0.0, (s, r) => s + r.calories);
  int get flaggedCount =>
      rows.where((r) => r.tier == ConfidenceTier.checkThis).length;
}

class AddSession extends Notifier<AddSessionState> {
  @override
  AddSessionState build() => const AddSessionState(
        rows: [],
        meal: Meal.snacks,
        source: AddSource.manual,
        status: AddStatus.idle,
      );

  void start(Meal meal, AddSource source) => state = AddSessionState(
        rows: const [],
        meal: meal,
        source: source,
        status: AddStatus.idle,
      );

  void setMeal(Meal meal) => state = state.copyWith(meal: meal);

  Future<void> parseText(String text) async {
    state = state.copyWith(status: AddStatus.parsing, rows: const []);
    try {
      final rows = await ref.read(apiProvider).parseText(text);
      state = state.copyWith(rows: rows, status: AddStatus.ready);
    } catch (e) {
      state = state.copyWith(status: AddStatus.error, error: '$e');
    }
  }

  void replaceRow(ReviewRow row) => state = state.copyWith(
        rows: [for (final r in state.rows) if (r.id == row.id) row else r],
      );

  /// Removes a row and returns it (with its index) so the caller can offer undo.
  (ReviewRow, int)? removeRow(String id) {
    final idx = state.rows.indexWhere((r) => r.id == id);
    if (idx < 0) return null;
    final removed = state.rows[idx];
    state = state.copyWith(rows: [...state.rows]..removeAt(idx));
    return (removed, idx);
  }

  void insertRow(ReviewRow row, int index) {
    final list = [...state.rows];
    list.insert(index.clamp(0, list.length), row);
    state = state.copyWith(rows: list);
  }

  Future<void> commit(DateTime date) async {
    state = state.copyWith(status: AddStatus.committing);
    final api = ref.read(apiProvider);
    final meal = state.meal;
    try {
      // Commit one row at a time, dropping each from the session as it succeeds, so
      // a retry after a partial failure never double-logs an already-committed row.
      for (final row in state.committable.toList()) {
        await api.commitRows(date: date, meal: meal, rows: [row]);
        state = state.copyWith(
            rows: [...state.rows]..removeWhere((r) => r.id == row.id));
      }
      // Success: clear the session so re-entry is clean and re-commit can't duplicate.
      state = AddSessionState(
          rows: const [], meal: meal, source: state.source, status: AddStatus.idle);
    } catch (e) {
      // Keep the remaining (uncommitted) rows visible; the caller surfaces the error.
      // Don't flip to AddStatus.error — that's the parse-error state and would wipe the rows.
      state = state.copyWith(status: AddStatus.ready);
      rethrow;
    }
  }
}

final addSessionProvider =
    NotifierProvider<AddSession, AddSessionState>(AddSession.new);
