using Sitos.Core;
using Sitos.Core.Entities;
using Xunit;

namespace Sitos.Tests;

public class NutritionCalcTests
{
    private static Food Nutella() => new()
    {
        Name = "Nutella",
        CaloriesPer100g = 539, ProteinPer100g = 6.3, CarbsPer100g = 57.5, FatPer100g = 30.9,
        ServingSizeGrams = 15
    };

    [Fact]
    public void ResolveGrams_grams_unit_is_quantity()
    {
        var e = new DiaryEntry { Food = Nutella(), Quantity = 30, Unit = QuantityUnit.Grams };
        Assert.Equal(30, e.ResolveGrams());
    }

    [Fact]
    public void ResolveGrams_servings_unit_uses_serving_size()
    {
        var e = new DiaryEntry { Food = Nutella(), Quantity = 2, Unit = QuantityUnit.Servings };
        Assert.Equal(30, e.ResolveGrams()); // 2 * 15g
    }

    [Fact]
    public void ResolveGrams_servings_without_serving_size_falls_back_to_100g()
    {
        var food = Nutella();
        food.ServingSizeGrams = null;
        var e = new DiaryEntry { Food = food, Quantity = 1.5, Unit = QuantityUnit.Servings };
        Assert.Equal(150, e.ResolveGrams()); // 1.5 * 100g notional
    }

    [Fact]
    public void Calories_scale_with_grams()
    {
        var e = new DiaryEntry { Food = Nutella(), Quantity = 30, Unit = QuantityUnit.Grams };
        var grams = e.ResolveGrams();
        Assert.Equal(161.7, Math.Round(e.Food!.CaloriesPer100g * grams / 100d, 1));
    }
}
