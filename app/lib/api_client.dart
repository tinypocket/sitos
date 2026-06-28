import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

import 'auth_service.dart';
import 'models.dart';

/// Thrown when a barcode/food isn't found anywhere (cache or providers).
class NotFoundException implements Exception {}

/// Talks to the Sitos API.
///
/// The default base URL targets an Android emulator, which reaches the host
/// machine at 10.0.2.2. Override via --dart-define=SITOS_API_BASE=... for a
/// physical device (use your machine's LAN IP) or a deployed environment.
class SitosApi {
  SitosApi({String? baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl ??
              const String.fromEnvironment('SITOS_API_BASE',
                  defaultValue: 'http://10.0.2.2:5000'),
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        )) {
    // Attach the Google ID token (when signed in) as a Bearer credential.
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final token = AuthService.instance.idToken;
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    }));
  }

  final Dio _dio;
  static final _dateFmt = DateFormat('yyyy-MM-dd');

  Future<Food> getFoodByBarcode(String code) async {
    try {
      final res = await _dio.get('/api/foods/barcode/$code');
      return Food.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw NotFoundException();
      rethrow;
    }
  }

  Future<List<Food>> searchFoods(String query) async {
    final res = await _dio.get('/api/foods/search',
        queryParameters: {'q': query});
    return (res.data as List)
        .map((e) => Food.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Food> createUserFood(Map<String, dynamic> body) async {
    final res = await _dio.post('/api/foods', data: body);
    return Food.fromJson(res.data as Map<String, dynamic>);
  }

  Future<DiaryDay> getDiary(DateTime date) async {
    final res = await _dio.get('/api/diary',
        queryParameters: {'date': _dateFmt.format(date)});
    return DiaryDay.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> addDiaryEntry({
    required String foodId,
    required DateTime date,
    required Meal meal,
    required double quantity,
    required QuantityUnit unit,
  }) async {
    await _dio.post('/api/diary', data: {
      'foodId': foodId,
      'date': _dateFmt.format(date),
      'meal': meal.index,
      'quantity': quantity,
      'unit': unit.index,
    });
  }

  Future<void> updateDiaryEntry({
    required String id,
    required String foodId,
    required DateTime date,
    required Meal meal,
    required double quantity,
    required QuantityUnit unit,
  }) async {
    await _dio.put('/api/diary/$id', data: {
      'foodId': foodId,
      'date': _dateFmt.format(date),
      'meal': meal.index,
      'quantity': quantity,
      'unit': unit.index,
    });
  }

  Future<void> deleteDiaryEntry(String id) async {
    await _dio.delete('/api/diary/$id');
  }

  Future<List<Food>> getRecentFoods() async {
    final res = await _dio.get('/api/diary/recent-foods');
    return (res.data as List)
        .map((e) => Food.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Goal?> getGoal() async {
    final res = await _dio.get('/api/profile/goal');
    if (res.statusCode == 204 || res.data == null) return null;
    return Goal.fromJson(res.data as Map<String, dynamic>);
  }

  // ----- Recipes -----
  Future<List<Recipe>> getRecipes() async {
    final res = await _dio.get('/api/recipes');
    return (res.data as List)
        .map((e) => Recipe.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Recipe> saveRecipe({
    String? id, // null = create
    required String name,
    required int servings,
    required List<({String foodId, double quantity, QuantityUnit unit})> ingredients,
  }) async {
    final body = {
      'name': name,
      'servings': servings,
      'ingredients': ingredients
          .map((i) => {'foodId': i.foodId, 'quantity': i.quantity, 'unit': i.unit.index})
          .toList(),
    };
    final res = id == null
        ? await _dio.post('/api/recipes', data: body)
        : await _dio.put('/api/recipes/$id', data: body);
    return Recipe.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteRecipe(String id) async {
    await _dio.delete('/api/recipes/$id');
  }

  Future<void> logRecipe({
    required String id,
    required DateTime date,
    required Meal meal,
    required double servings,
  }) async {
    await _dio.post('/api/recipes/$id/log', data: {
      'date': _dateFmt.format(date),
      'meal': meal.index,
      'servings': servings,
    });
  }

  Future<Goal> setGoal({
    required int dailyCalorieTarget,
    int? proteinTargetGrams,
    int? carbsTargetGrams,
    int? fatTargetGrams,
  }) async {
    final res = await _dio.put('/api/profile/goal', data: {
      'dailyCalorieTarget': dailyCalorieTarget,
      'proteinTargetGrams': proteinTargetGrams,
      'carbsTargetGrams': carbsTargetGrams,
      'fatTargetGrams': fatTargetGrams,
    });
    return Goal.fromJson(res.data as Map<String, dynamic>);
  }

  // ===== Entry experience (E2/E3) =====
  // TEMPORARY: parseText is a client-side parser that resolves each clause against
  // the live food DB (search). Replace with `POST /api/parse/text` when it lands.
  // commitRows loops the existing single-add endpoint; replace with
  // `POST /api/diary/batch`. matchFoods aliases search for the swap-match sheet.

  static const _massVolumeGrams = <String, double>{
    'g': 1, 'gram': 1, 'grams': 1, 'kg': 1000,
    'oz': 28.35, 'ounce': 28.35, 'ounces': 28.35, 'lb': 453.6,
    'tbsp': 15, 'tablespoon': 15, 'tablespoons': 15,
    'tsp': 5, 'teaspoon': 5, 'teaspoons': 5,
    'cup': 240, 'cups': 240, 'ml': 1, 'l': 1000,
  };
  static const _sizeWords = {
    'small', 'medium', 'large', 'slice', 'slices',
    'clove', 'cloves', 'piece', 'pieces',
  };
  static const _numberWords = <String, double>{
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
    'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'dozen': 12,
    'half': 0.5, 'quarter': 0.25, 'couple': 2, 'few': 3, 'some': 1,
  };

  Future<List<ReviewRow>> parseText(String text) async {
    final clauses = text
        // case-insensitive "and" so "AND"/"and" split consistently
        .split(RegExp(r',|\band\b|\n', caseSensitive: false))
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .take(25) // cap a pasted wall of text
        .toList();
    // Resolve clauses concurrently (each does one food search) for a faster parse.
    return Future.wait([
      for (var i = 0; i < clauses.length; i++) _resolveClause(clauses[i], i),
    ]);
  }

  Future<ReviewRow> _resolveClause(String clause, int index) async {
    // Clean + expand tokens: strip trailing punctuation ("tbsp." → "tbsp", "2." → "2"),
    // and split a number glued to a unit/word ("100g" → 100, g ; "2tbsp" → 2, tbsp).
    final tokens = <String>[];
    for (final raw in clause.toLowerCase().split(RegExp(r'\s+'))) {
      var tok = raw
          .replaceAll(RegExp(r'[^a-z0-9/.]'), '') // keep . and / for 1.5 and 1/2
          .replaceAll(RegExp(r'[./]+$'), ''); // but drop a trailing . or /
      if (tok.isEmpty) continue;
      final glued = RegExp(r'^(\d*\.?\d+)([a-z].*)$').firstMatch(tok);
      if (glued != null) {
        tokens.add(glued.group(1)!);
        tokens.add(glued.group(2)!);
      } else {
        tokens.add(tok);
      }
    }

    double? qty;
    String? sizeLabel;
    double? massGrams;
    bool vague = false;
    final nameTokens = <String>[];

    for (final tok in tokens) {
      final asNum = double.tryParse(tok);
      final frac = RegExp(r'^(\d+)/(\d+)$').firstMatch(tok);
      if (qty == null && asNum != null) {
        qty = asNum;
        continue;
      }
      if (qty == null && frac != null) {
        qty = double.parse(frac.group(1)!) / double.parse(frac.group(2)!);
        continue;
      }
      if (qty == null && _numberWords.containsKey(tok)) {
        qty = _numberWords[tok];
        if (tok == 'some') vague = true;
        continue;
      }
      if (massGrams == null && _massVolumeGrams.containsKey(tok)) {
        massGrams = _massVolumeGrams[tok];
        continue;
      }
      if (sizeLabel == null && _sizeWords.contains(tok)) {
        sizeLabel = tok;
        continue;
      }
      if (tok == 'of' || tok == 'a' || tok == 'an') continue; // filler
      nameTokens.add(tok);
    }

    final name = nameTokens.join(' ').trim();
    List<Food> candidates = const [];
    if (name.isNotEmpty) {
      try {
        candidates = await searchFoods(name);
      } catch (_) {/* offline / no match — leave empty */}
    }
    final match = candidates.isNotEmpty ? candidates.first : null;

    final count = qty ?? 1;
    final double grams;
    final QuantityUnit unit;
    if (massGrams != null) {
      grams = count * massGrams;
      unit = QuantityUnit.grams;
    } else if (match?.servingSizeGrams != null) {
      grams = count * match!.servingSizeGrams!;
      unit = QuantityUnit.countSize;
    } else {
      grams = count * 100; // rough default until E6/DB serving data
      unit = QuantityUnit.countSize;
    }

    final kcal = match == null ? 0.0 : match.caloriesPer100g * grams / 100.0;
    final tier = match == null
        ? ConfidenceTier.noMatch
        : (qty == null || vague)
            ? ConfidenceTier.checkThis
            : ConfidenceTier.estimated;

    return ReviewRow(
      id: 'row_$index',
      rawText: clause,
      match: match,
      candidates: candidates.take(8).toList(),
      quantity: massGrams != null ? grams : count,
      unit: unit,
      sizeLabel: sizeLabel,
      grams: grams,
      calories: kcal,
      tier: tier,
    );
  }

  Future<List<Food>> matchFoods(String query) => searchFoods(query);

  Future<void> commitRows({
    required DateTime date,
    required Meal meal,
    required List<ReviewRow> rows,
  }) async {
    for (final r in rows) {
      final f = r.match;
      if (f == null || !r.tier.commits) continue;
      await addDiaryEntry(
        foodId: f.id,
        date: date,
        meal: meal,
        quantity: r.grams,
        unit: QuantityUnit.grams,
      );
    }
  }
}
