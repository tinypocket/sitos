namespace Sitos.Core.Entities;

/// <summary>
/// A user-defined dish made of ingredients, split into a number of servings. Its per-serving
/// nutrition is materialised into a backing <see cref="Food"/> (<see cref="BackingFoodId"/>,
/// <see cref="FoodSource.Recipe"/>) so a serving can be logged to the diary like any other food.
/// </summary>
public class Recipe
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }

    public string Name { get; set; } = string.Empty;

    /// <summary>How many portions the whole recipe makes (e.g. number of people).</summary>
    public int Servings { get; set; } = 1;

    /// <summary>The per-serving food this recipe maintains; logged to the diary.</summary>
    public Guid BackingFoodId { get; set; }
    public Food? BackingFood { get; set; }

    public List<RecipeIngredient> Ingredients { get; set; } = [];

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
}

/// <summary>One ingredient in a <see cref="Recipe"/>: a food and how much of it.</summary>
public class RecipeIngredient
{
    public Guid Id { get; set; }
    public Guid RecipeId { get; set; }

    public Guid FoodId { get; set; }
    public Food? Food { get; set; }

    public double Quantity { get; set; }
    public QuantityUnit Unit { get; set; }
}
