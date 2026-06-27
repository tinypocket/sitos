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
            e.Id, e.Date, e.Quantity, e.Unit,
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
    double Quantity,
    QuantityUnit Unit);

public record DiaryDayDto(
    DateOnly Date,
    double TotalCalories,
    double TotalProtein,
    double TotalCarbs,
    double TotalFat,
    int? GoalCalories,
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
