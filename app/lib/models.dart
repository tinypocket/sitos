// Data models mirroring the Sitos API DTOs.

/// Matches the server's QuantityUnit enum (servings=0, grams=1).
/// [countSize] is a UI-only input mode (e.g. "3 medium"); it is resolved to grams
/// before anything is sent to the server, so the server never sees index 2.
enum QuantityUnit {
  servings, // 0
  grams, // 1
  countSize, // UI-only
}

/// How confident we are in an AI-/heuristic-proposed row. Server-provided per row
/// (mirrors the `verifiedStatus` int on [Food]); the client never invents it.
/// One visual treatment everywhere AI proposes something — see [ConfidenceChip].
enum ConfidenceTier {
  verified,
  estimated,
  checkThis,
  noMatch;

  /// Screen-reader / accessibility label.
  String get srLabel => switch (this) {
        ConfidenceTier.verified => 'Verified',
        ConfidenceTier.estimated => 'Estimated, please check',
        ConfidenceTier.checkThis => 'Needs a check',
        ConfidenceTier.noMatch => 'No database match',
      };

  /// No-match rows have no nutrition, so they're excluded from a commit.
  bool get commits => this != ConfidenceTier.noMatch;
}

/// A single proposed line in the shared review & confirm surface (E2). Immutable;
/// the add session replaces rows on edit so Riverpod rebuilds.
class ReviewRow {
  final String id; // local id for the session
  final String rawText; // the clause the user typed, e.g. "half a cup of cottage cheese"
  final Food? match; // the chosen food, null when no match
  final List<Food> candidates; // alternatives for the swap-match sheet
  final double quantity;
  final QuantityUnit unit;
  final String? sizeLabel; // for count+size, e.g. "medium"
  final double grams; // resolved grams
  final double calories;
  final ConfidenceTier tier;

  const ReviewRow({
    required this.id,
    required this.rawText,
    required this.match,
    required this.candidates,
    required this.quantity,
    required this.unit,
    this.sizeLabel,
    required this.grams,
    required this.calories,
    required this.tier,
  });

  bool get resolved => tier.commits && match != null;

  ReviewRow copyWith({
    Food? match,
    List<Food>? candidates,
    double? quantity,
    QuantityUnit? unit,
    String? sizeLabel,
    double? grams,
    double? calories,
    ConfidenceTier? tier,
  }) =>
      ReviewRow(
        id: id,
        rawText: rawText,
        match: match ?? this.match,
        candidates: candidates ?? this.candidates,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        sizeLabel: sizeLabel ?? this.sizeLabel,
        grams: grams ?? this.grams,
        calories: calories ?? this.calories,
        tier: tier ?? this.tier,
      );
}

/// Matches the server's Meal enum.
enum Meal {
  breakfast, // 0
  lunch, // 1
  dinner, // 2
  snacks; // 3

  String get label => switch (this) {
        Meal.breakfast => 'Breakfast',
        Meal.lunch => 'Lunch',
        Meal.dinner => 'Dinner',
        Meal.snacks => 'Snacks',
      };

  /// A sensible default meal for the current time of day.
  static Meal forTimeOfDay(DateTime now) {
    final h = now.hour;
    if (h < 11) return Meal.breakfast;
    if (h < 15) return Meal.lunch;
    if (h < 21) return Meal.dinner;
    return Meal.snacks;
  }
}

class Food {
  final String id;
  final String? barcode;
  final String name;
  final String? brand;
  final double? servingSizeGrams;
  final String? servingSizeLabel;
  final double caloriesPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final int source;
  final int verifiedStatus;

  const Food({
    required this.id,
    this.barcode,
    required this.name,
    this.brand,
    this.servingSizeGrams,
    this.servingSizeLabel,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    required this.source,
    required this.verifiedStatus,
  });

  factory Food.fromJson(Map<String, dynamic> j) => Food(
        id: j['id'] as String,
        barcode: j['barcode'] as String?,
        name: j['name'] as String,
        brand: j['brand'] as String?,
        servingSizeGrams: (j['servingSizeGrams'] as num?)?.toDouble(),
        servingSizeLabel: j['servingSizeLabel'] as String?,
        caloriesPer100g: (j['caloriesPer100g'] as num).toDouble(),
        proteinPer100g: (j['proteinPer100g'] as num).toDouble(),
        carbsPer100g: (j['carbsPer100g'] as num).toDouble(),
        fatPer100g: (j['fatPer100g'] as num).toDouble(),
        source: j['source'] as int,
        verifiedStatus: j['verifiedStatus'] as int,
      );
}

class DiaryEntry {
  final String id;
  final DateTime date;
  final Meal meal;
  final double quantity;
  final QuantityUnit unit;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final Food food;

  const DiaryEntry({
    required this.id,
    required this.date,
    required this.meal,
    required this.quantity,
    required this.unit,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.food,
  });

  factory DiaryEntry.fromJson(Map<String, dynamic> j) => DiaryEntry(
        id: j['id'] as String,
        date: DateTime.parse(j['date'] as String),
        meal: Meal.values[j['meal'] as int],
        quantity: (j['quantity'] as num).toDouble(),
        unit: QuantityUnit.values[j['unit'] as int],
        calories: (j['calories'] as num).toDouble(),
        protein: (j['protein'] as num).toDouble(),
        carbs: (j['carbs'] as num).toDouble(),
        fat: (j['fat'] as num).toDouble(),
        food: Food.fromJson(j['food'] as Map<String, dynamic>),
      );
}

class DiaryDay {
  final DateTime date;
  final double totalCalories;
  final double totalProtein;
  final double totalCarbs;
  final double totalFat;
  final int? goalCalories;
  final int? goalProtein;
  final int? goalCarbs;
  final int? goalFat;
  final List<DiaryEntry> entries;

  const DiaryDay({
    required this.date,
    required this.totalCalories,
    required this.totalProtein,
    required this.totalCarbs,
    required this.totalFat,
    this.goalCalories,
    this.goalProtein,
    this.goalCarbs,
    this.goalFat,
    required this.entries,
  });

  factory DiaryDay.fromJson(Map<String, dynamic> j) => DiaryDay(
        date: DateTime.parse(j['date'] as String),
        totalCalories: (j['totalCalories'] as num).toDouble(),
        totalProtein: (j['totalProtein'] as num).toDouble(),
        totalCarbs: (j['totalCarbs'] as num).toDouble(),
        totalFat: (j['totalFat'] as num).toDouble(),
        goalCalories: j['goalCalories'] as int?,
        goalProtein: j['goalProtein'] as int?,
        goalCarbs: j['goalCarbs'] as int?,
        goalFat: j['goalFat'] as int?,
        entries: (j['entries'] as List)
            .map((e) => DiaryEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class RecipeIngredient {
  final String foodId;
  final String foodName;
  final double quantity;
  final QuantityUnit unit;
  final double calories;

  const RecipeIngredient({
    required this.foodId,
    required this.foodName,
    required this.quantity,
    required this.unit,
    required this.calories,
  });

  factory RecipeIngredient.fromJson(Map<String, dynamic> j) => RecipeIngredient(
        foodId: j['foodId'] as String,
        foodName: j['foodName'] as String,
        quantity: (j['quantity'] as num).toDouble(),
        unit: QuantityUnit.values[j['unit'] as int],
        calories: (j['calories'] as num).toDouble(),
      );
}

class Recipe {
  final String id;
  final String name;
  final int servings;
  final double perServingCalories;
  final double perServingProtein;
  final double perServingCarbs;
  final double perServingFat;
  final List<RecipeIngredient> ingredients;

  const Recipe({
    required this.id,
    required this.name,
    required this.servings,
    required this.perServingCalories,
    required this.perServingProtein,
    required this.perServingCarbs,
    required this.perServingFat,
    required this.ingredients,
  });

  factory Recipe.fromJson(Map<String, dynamic> j) => Recipe(
        id: j['id'] as String,
        name: j['name'] as String,
        servings: j['servings'] as int,
        perServingCalories: (j['perServingCalories'] as num).toDouble(),
        perServingProtein: (j['perServingProtein'] as num).toDouble(),
        perServingCarbs: (j['perServingCarbs'] as num).toDouble(),
        perServingFat: (j['perServingFat'] as num).toDouble(),
        ingredients: (j['ingredients'] as List)
            .map((e) => RecipeIngredient.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Goal {
  final int dailyCalorieTarget;
  final int? proteinTargetGrams;
  final int? carbsTargetGrams;
  final int? fatTargetGrams;

  const Goal({
    required this.dailyCalorieTarget,
    this.proteinTargetGrams,
    this.carbsTargetGrams,
    this.fatTargetGrams,
  });

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
        dailyCalorieTarget: j['dailyCalorieTarget'] as int,
        proteinTargetGrams: j['proteinTargetGrams'] as int?,
        carbsTargetGrams: j['carbsTargetGrams'] as int?,
        fatTargetGrams: j['fatTargetGrams'] as int?,
      );
}
