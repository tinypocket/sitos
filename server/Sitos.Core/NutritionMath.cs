namespace Sitos.Core;

public static class NutritionMath
{
    /// <summary>
    /// Grams represented by a quantity in the given unit. Servings resolve via the food's serving
    /// size, falling back to a 100 g notional serving when unknown. Shared by diary entries and
    /// recipe ingredients so they compute identically.
    /// </summary>
    public static double ResolveGrams(double quantity, QuantityUnit unit, double? servingSizeGrams) =>
        unit switch
        {
            QuantityUnit.Grams => quantity,
            QuantityUnit.Servings => quantity * (servingSizeGrams ?? 100d),
            _ => quantity
        };
}
