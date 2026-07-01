namespace Sitos.Core;

/// <summary>
/// Result of parsing a meal photo. Each <see cref="DetectedFoodItem"/> in <see cref="Items"/> is one
/// distinct food/dish the vision model identified, with an estimated portion (grams) and the calories +
/// macros for that portion. In <c>breakdown</c> mode there is typically one item per ingredient/dish; in
/// <c>estimate</c> mode there is exactly one item (the whole dish) carrying a calorie range.
/// <see cref="Suggestions"/> holds lower-confidence "maybe" ingredients the model did NOT include in
/// <see cref="Items"/> (e.g. a hidden sauce, oil, garnish, or likely side) — same shape as items, shown
/// to the user as optional add-ons. Always non-null; empty in <c>estimate</c> mode.
/// </summary>
public sealed record MealParseResult(
    IReadOnlyList<DetectedFoodItem> Items,
    IReadOnlyList<DetectedFoodItem> Suggestions);

/// <summary>
/// One food/dish detected in a meal photo. Calories and macros are the AI's estimate for the
/// detected <see cref="Grams"/> portion (not per-100g). <see cref="CaloriesMin"/>/<see cref="CaloriesMax"/>
/// are only populated in <c>estimate</c> mode (a low/high band for the dish total).
/// <see cref="Alternates"/> are 2–3 alternative food NAMES the user could swap to (e.g. for
/// "grilled chicken breast" → "fried chicken breast", "chicken thigh"); never duplicating
/// <see cref="Name"/>. Always non-null; may be empty.
/// </summary>
public sealed record DetectedFoodItem(
    string Name,
    double Grams,
    double Calories,
    double Protein,
    double Carbs,
    double Fat,
    string Confidence,
    double? CaloriesMin,
    double? CaloriesMax,
    IReadOnlyList<string> Alternates);

/// <summary>Parsing modes for the meal-photo endpoint. Wire values are the lowercase names.</summary>
public static class MealParseMode
{
    /// <summary>Detect each distinct food/ingredient with its own portion + nutrition.</summary>
    public const string Breakdown = "breakdown";

    /// <summary>A single dish row with a total estimate and a [min,max] calorie range.</summary>
    public const string Estimate = "estimate";
}

/// <summary>Confidence levels for a detected item. Wire values are these exact strings.</summary>
public static class MealConfidence
{
    public const string Verified = "verified";
    public const string Estimated = "estimated";
    public const string CheckThis = "checkThis";
}

/// <summary>Raised when the vision model call fails or returns an unusable response.</summary>
public sealed class MealPhotoParseException(string message) : Exception(message);
