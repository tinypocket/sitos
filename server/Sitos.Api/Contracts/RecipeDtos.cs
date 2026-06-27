using Sitos.Core;
using Sitos.Core.Entities;

namespace Sitos.Api.Contracts;

public record RecipeIngredientDto(
    Guid FoodId,
    string FoodName,
    double Quantity,
    QuantityUnit Unit,
    double Calories)
{
    public static RecipeIngredientDto From(RecipeIngredient i)
    {
        var food = i.Food!;
        var grams = NutritionMath.ResolveGrams(i.Quantity, i.Unit, food.ServingSizeGrams);
        return new RecipeIngredientDto(
            i.FoodId, food.Name, i.Quantity, i.Unit,
            Math.Round(food.CaloriesPer100g * grams / 100d, 1));
    }
}

public record RecipeDto(
    Guid Id,
    string Name,
    int Servings,
    double PerServingCalories,
    double PerServingProtein,
    double PerServingCarbs,
    double PerServingFat,
    IReadOnlyList<RecipeIngredientDto> Ingredients)
{
    public static RecipeDto From(Recipe r)
    {
        var servings = Math.Max(1, r.Servings);
        double cal = 0, p = 0, c = 0, f = 0;
        foreach (var i in r.Ingredients)
        {
            var food = i.Food!;
            var factor = NutritionMath.ResolveGrams(i.Quantity, i.Unit, food.ServingSizeGrams) / 100d;
            cal += food.CaloriesPer100g * factor;
            p += food.ProteinPer100g * factor;
            c += food.CarbsPer100g * factor;
            f += food.FatPer100g * factor;
        }
        return new RecipeDto(
            r.Id, r.Name, servings,
            Math.Round(cal / servings, 1),
            Math.Round(p / servings, 1),
            Math.Round(c / servings, 1),
            Math.Round(f / servings, 1),
            r.Ingredients.Select(RecipeIngredientDto.From).ToList());
    }
}

public record CreateIngredientRequest(Guid FoodId, double Quantity, QuantityUnit Unit);

public record CreateRecipeRequest(
    string Name,
    int Servings,
    IReadOnlyList<CreateIngredientRequest> Ingredients);

public record LogRecipeRequest(DateOnly Date, Meal Meal, double Servings);
