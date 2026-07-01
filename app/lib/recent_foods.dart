import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Serializes a [Food] to the minimal map we persist for recents. Kept here (rather
/// than on the model) so the recents feature owns its own storage format. Mirrors
/// [Food.fromJson] field-for-field so [_foodFromMap] round-trips cleanly.
Map<String, dynamic> _foodToMap(Food f) => {
      'id': f.id,
      'barcode': f.barcode,
      'name': f.name,
      'brand': f.brand,
      'servingSizeGrams': f.servingSizeGrams,
      'servingSizeLabel': f.servingSizeLabel,
      'caloriesPer100g': f.caloriesPer100g,
      'proteinPer100g': f.proteinPer100g,
      'carbsPer100g': f.carbsPer100g,
      'fatPer100g': f.fatPer100g,
      'source': f.source,
      'verifiedStatus': f.verifiedStatus,
    };

Food _foodFromMap(Map<String, dynamic> j) => Food.fromJson(j);

/// How many entries each recents list keeps.
const _cap = 8;

/// The last few non-empty search query strings, most-recent first, de-duped
/// case-insensitively and capped at [_cap]. Persisted via SharedPreferences.
class RecentSearchesNotifier extends Notifier<List<String>> {
  static const _kKey = 'search.recentQueries';
  SharedPreferences? _prefs;

  @override
  List<String> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    state = _prefs!.getStringList(_kKey) ?? const [];
  }

  Future<void> record(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final next = [
      q,
      ...state.where((e) => e.toLowerCase() != q.toLowerCase()),
    ].take(_cap).toList();
    state = next;
    (_prefs ??= await SharedPreferences.getInstance()).setStringList(_kKey, next);
  }
}

final recentSearchesProvider =
    NotifierProvider<RecentSearchesNotifier, List<String>>(
        RecentSearchesNotifier.new);

/// The last few foods the user picked, most-recent first, de-duped by [Food.id]
/// and capped at [_cap]. Stored as a list of JSON strings.
class RecentFoodsNotifier extends Notifier<List<Food>> {
  static const _kKey = 'search.recentFoods';
  SharedPreferences? _prefs;

  @override
  List<Food> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getStringList(_kKey) ?? const [];
    state = raw.map(_decode).whereType<Food>().toList();
  }

  static Food? _decode(String s) {
    try {
      return _foodFromMap(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> record(Food food) async {
    final next = [
      food,
      ...state.where((f) => f.id != food.id),
    ].take(_cap).toList();
    state = next;
    (_prefs ??= await SharedPreferences.getInstance()).setStringList(
      _kKey,
      next.map((f) => jsonEncode(_foodToMap(f))).toList(),
    );
  }
}

/// Named `pickedFoodsProvider` (not `recentFoods…`) to avoid colliding with the
/// diary-derived `recentFoodsProvider` in providers.dart.
final pickedFoodsProvider =
    NotifierProvider<RecentFoodsNotifier, List<Food>>(RecentFoodsNotifier.new);
