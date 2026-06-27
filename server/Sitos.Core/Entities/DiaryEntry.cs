namespace Sitos.Core.Entities;

/// <summary>A single logged food in a user's daily diary.</summary>
public class DiaryEntry
{
    public Guid Id { get; set; }

    public Guid UserId { get; set; }

    public Guid FoodId { get; set; }
    public Food? Food { get; set; }

    public DateOnly Date { get; set; }

    public Meal Meal { get; set; }

    /// <summary>Amount consumed, interpreted according to <see cref="Unit"/>.</summary>
    public double Quantity { get; set; }
    public QuantityUnit Unit { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    /// <summary>Grams represented by this entry, resolving servings via the food's serving size.</summary>
    public double ResolveGrams() => NutritionMath.ResolveGrams(Quantity, Unit, Food?.ServingSizeGrams);
}
