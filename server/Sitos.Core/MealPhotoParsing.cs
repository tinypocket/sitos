namespace Sitos.Core;

/// <summary>
/// Result of parsing a meal photo. Each <see cref="DetectedFoodItem"/> is one distinct food/dish
/// the vision model identified, with an estimated portion (grams) and the calories + macros for
/// that portion. In <c>breakdown</c> mode there is typically one item per ingredient/dish; in
/// <c>estimate</c> mode there is exactly one item (the whole dish) carrying a calorie range.
/// </summary>
public sealed record MealParseResult(IReadOnlyList<DetectedFoodItem> Items);

/// <summary>
/// One food/dish detected in a meal photo. Calories and macros are the AI's estimate for the
/// detected <see cref="Grams"/> portion (not per-100g). <see cref="CaloriesMin"/>/<see cref="CaloriesMax"/>
/// are only populated in <c>estimate</c> mode (a low/high band for the dish total).
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
    double? CaloriesMax);

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
