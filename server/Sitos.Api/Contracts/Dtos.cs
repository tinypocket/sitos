using Sitos.Core;
using Sitos.Core.Entities;

namespace Sitos.Api.Contracts;

public record FoodDto(
    Guid Id,
    string? Barcode,
    string Name,
    string? Brand,
    double? ServingSizeGrams,
    string? ServingSizeLabel,
    double CaloriesPer100g,
    double ProteinPer100g,
    double CarbsPer100g,
    double FatPer100g,
    FoodSource Source,
    VerifiedStatus VerifiedStatus)
{
    public static FoodDto From(Food f) => new(
        f.Id, f.Barcode, f.Name, f.Brand, f.ServingSizeGrams, f.ServingSizeLabel,
        f.CaloriesPer100g, f.ProteinPer100g, f.CarbsPer100g, f.FatPer100g, f.Source, f.VerifiedStatus);
}

/// <summary>
/// Request to read a Nutrition Facts label photo. <see cref="ImageBase64"/> is the base64 of the
/// image (no data: prefix); <see cref="MimeType"/> defaults to image/jpeg when omitted.
/// </summary>
public record ExtractLabelRequest(string ImageBase64, string? MimeType);

/// <summary>
/// Request to parse a meal photo. <see cref="ImageBase64"/> is the base64 of the image (no data:
/// prefix); <see cref="MimeType"/> defaults to image/jpeg when omitted; <see cref="Mode"/> is
/// "breakdown" (per-ingredient rows) or "estimate" (single dish row), defaulting to "breakdown".
/// </summary>
public record ParsePhotoRequest(string ImageBase64, string? MimeType, string? Mode);

/// <summary>
/// One reviewable row from a parsed meal photo. <see cref="Food"/> is the full, persisted Food DTO
/// (same shape as the barcode endpoint) so the client can log it via the existing diary flow.
/// <see cref="Calories"/> is the calories for <see cref="Grams"/> of that food. <see cref="CaloriesRange"/>
/// is [min,max] and only present in estimate mode.
/// </summary>
public record ParsedRowDto(
    FoodDto Food,
    double Grams,
    double Calories,
    string Confidence,
    double[]? CaloriesRange);

/// <summary>
/// Response for <c>POST /api/parse/photo</c>. <see cref="Rows"/> is empty when no food was detected
/// (the client shows a no-food screen); breakdown → many rows; estimate → exactly one row.
/// <see cref="Suggestions"/> is a parallel list (same <see cref="ParsedRowDto"/> shape) of lower-confidence
/// "maybe" ingredients the model did NOT include in <see cref="Rows"/> — the client shows these as greyed
/// suggestions the user can tap to add. Always present; empty in estimate mode or when there are none.
/// </summary>
public record ParsePhotoResponse(
    IReadOnlyList<ParsedRowDto> Rows,
    IReadOnlyList<ParsedRowDto> Suggestions);

public record CreateUserFoodRequest(
    string Name,
    string? Brand,
    string? Barcode,
    double? ServingSizeGrams,
    string? ServingSizeLabel,
    double CaloriesPer100g,
    double ProteinPer100g,
    double CarbsPer100g,
    double FatPer100g);

public record DiaryEntryDto(
    Guid Id,
    DateOnly Date,
    Meal Meal,
    double Quantity,
    QuantityUnit Unit,
    double Calories,
    double Protein,
    double Carbs,
    double Fat,
    FoodDto Food)
{
    public static DiaryEntryDto From(DiaryEntry e)
    {
        var factor = e.ResolveGrams() / 100d;
        var food = e.Food!;
        return new DiaryEntryDto(
            e.Id, e.Date, e.Meal, e.Quantity, e.Unit,
            Math.Round(food.CaloriesPer100g * factor, 1),
            Math.Round(food.ProteinPer100g * factor, 1),
            Math.Round(food.CarbsPer100g * factor, 1),
            Math.Round(food.FatPer100g * factor, 1),
            FoodDto.From(food));
    }
}

public record CreateDiaryEntryRequest(
    Guid FoodId,
    DateOnly Date,
    Meal Meal,
    double Quantity,
    QuantityUnit Unit);

public record DiaryDayDto(
    DateOnly Date,
    double TotalCalories,
    double TotalProtein,
    double TotalCarbs,
    double TotalFat,
    int? GoalCalories,
    int? GoalProtein,
    int? GoalCarbs,
    int? GoalFat,
    IReadOnlyList<DiaryEntryDto> Entries);

public record GoalDto(
    int DailyCalorieTarget,
    int? ProteinTargetGrams,
    int? CarbsTargetGrams,
    int? FatTargetGrams)
{
    public static GoalDto From(Goal g) =>
        new(g.DailyCalorieTarget, g.ProteinTargetGrams, g.CarbsTargetGrams, g.FatTargetGrams);
}
