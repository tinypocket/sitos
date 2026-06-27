using Sitos.Core.Entities;

namespace Sitos.Core.Abstractions;

public record IngredientInput(Guid FoodId, double Quantity, QuantityUnit Unit);
public record RecipeInput(string Name, int Servings, IReadOnlyList<IngredientInput> Ingredients);

/// <summary>
/// Manages recipes and keeps each recipe's per-serving backing <see cref="Food"/> in sync, so a
/// serving can be logged to the diary like any other food.
/// </summary>
public interface IRecipeService
{
    Task<Recipe> CreateAsync(Guid userId, RecipeInput input, CancellationToken ct = default);

    /// <summary>Replace a recipe's name/servings/ingredients. Null if not found / not owned.</summary>
    Task<Recipe?> UpdateAsync(Guid userId, Guid recipeId, RecipeInput input, CancellationToken ct = default);

    Task<bool> DeleteAsync(Guid userId, Guid recipeId, CancellationToken ct = default);

    /// <summary>Log <paramref name="servings"/> of a recipe to the diary. Null if not found.</summary>
    Task<DiaryEntry?> LogAsync(Guid userId, Guid recipeId, DateOnly date, Meal meal,
        double servings, CancellationToken ct = default);
}
