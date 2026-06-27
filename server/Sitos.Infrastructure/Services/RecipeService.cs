using Microsoft.EntityFrameworkCore;
using Sitos.Core;
using Sitos.Core.Abstractions;
using Sitos.Core.Entities;

namespace Sitos.Infrastructure.Services;

public class RecipeService(SitosDbContext db) : IRecipeService
{
    public async Task<Recipe> CreateAsync(Guid userId, RecipeInput input, CancellationToken ct = default)
    {
        var now = DateTimeOffset.UtcNow;
        var recipe = new Recipe
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Name = input.Name.Trim(),
            Servings = Math.Max(1, input.Servings),
            BackingFoodId = Guid.NewGuid(),
            CreatedAt = now,
            UpdatedAt = now,
            Ingredients = input.Ingredients
                .Select(i => new RecipeIngredient
                {
                    Id = Guid.NewGuid(),
                    FoodId = i.FoodId,
                    Quantity = i.Quantity,
                    Unit = i.Unit
                })
                .ToList()
        };

        var backing = new Food { Id = recipe.BackingFoodId, CreatedAt = now };
        db.Foods.Add(backing);
        db.Recipes.Add(recipe);
        await RecomputeBackingAsync(recipe, backing, userId, ct);
        await db.SaveChangesAsync(ct);
        return recipe;
    }

    public async Task<Recipe?> UpdateAsync(Guid userId, Guid recipeId, RecipeInput input, CancellationToken ct = default)
    {
        var recipe = await db.Recipes.Include(r => r.Ingredients)
            .FirstOrDefaultAsync(r => r.Id == recipeId && r.UserId == userId, ct);
        if (recipe is null) return null;

        recipe.Name = input.Name.Trim();
        recipe.Servings = Math.Max(1, input.Servings);
        recipe.UpdatedAt = DateTimeOffset.UtcNow;

        db.RecipeIngredients.RemoveRange(recipe.Ingredients);
        recipe.Ingredients = input.Ingredients
            .Select(i => new RecipeIngredient
            {
                Id = Guid.NewGuid(),
                RecipeId = recipe.Id,
                FoodId = i.FoodId,
                Quantity = i.Quantity,
                Unit = i.Unit
            })
            .ToList();

        var backing = await db.Foods.FirstAsync(f => f.Id == recipe.BackingFoodId, ct);
        await RecomputeBackingAsync(recipe, backing, userId, ct);
        await db.SaveChangesAsync(ct);
        return recipe;
    }

    public async Task<bool> DeleteAsync(Guid userId, Guid recipeId, CancellationToken ct = default)
    {
        var recipe = await db.Recipes.FirstOrDefaultAsync(r => r.Id == recipeId && r.UserId == userId, ct);
        if (recipe is null) return false;
        db.Recipes.Remove(recipe); // ingredients cascade
        await db.SaveChangesAsync(ct);
        // The backing food is left in place (a diary entry may reference it historically).
        return true;
    }

    public async Task<DiaryEntry?> LogAsync(Guid userId, Guid recipeId, DateOnly date, Meal meal,
        double servings, CancellationToken ct = default)
    {
        var recipe = await db.Recipes.FirstOrDefaultAsync(r => r.Id == recipeId && r.UserId == userId, ct);
        if (recipe is null) return null;

        var entry = new DiaryEntry
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            FoodId = recipe.BackingFoodId,
            Date = date,
            Meal = meal,
            Quantity = servings <= 0 ? 1 : servings,
            Unit = QuantityUnit.Servings, // backing food's serving = one recipe portion
            CreatedAt = DateTimeOffset.UtcNow
        };
        db.DiaryEntries.Add(entry);
        await db.SaveChangesAsync(ct);
        await db.Entry(entry).Reference(e => e.Food).LoadAsync(ct);
        return entry;
    }

    /// <summary>Recompute the recipe's per-serving backing food from its ingredients' foods.</summary>
    private async Task RecomputeBackingAsync(Recipe recipe, Food backing, Guid userId, CancellationToken ct)
    {
        var foodIds = recipe.Ingredients.Select(i => i.FoodId).Distinct().ToList();
        var foods = await db.Foods.Where(f => foodIds.Contains(f.Id))
            .ToDictionaryAsync(f => f.Id, ct);

        double totalGrams = 0, cal = 0, protein = 0, carbs = 0, fat = 0;
        foreach (var ing in recipe.Ingredients)
        {
            if (!foods.TryGetValue(ing.FoodId, out var food)) continue;
            var grams = NutritionMath.ResolveGrams(ing.Quantity, ing.Unit, food.ServingSizeGrams);
            var factor = grams / 100d;
            totalGrams += grams;
            cal += food.CaloriesPer100g * factor;
            protein += food.ProteinPer100g * factor;
            carbs += food.CarbsPer100g * factor;
            fat += food.FatPer100g * factor;
        }

        var servings = Math.Max(1, recipe.Servings);
        backing.Name = recipe.Name;
        backing.Source = FoodSource.Recipe;
        backing.CreatedByUserId = userId;
        backing.ServingSizeGrams = totalGrams > 0 ? totalGrams / servings : null;
        backing.ServingSizeLabel = $"1 of {servings} serving(s)";
        // Store per-100g density so logging N servings scales correctly via DiaryEntry math.
        backing.CaloriesPer100g = totalGrams > 0 ? cal / totalGrams * 100 : 0;
        backing.ProteinPer100g = totalGrams > 0 ? protein / totalGrams * 100 : 0;
        backing.CarbsPer100g = totalGrams > 0 ? carbs / totalGrams * 100 : 0;
        backing.FatPer100g = totalGrams > 0 ? fat / totalGrams * 100 : 0;
        backing.UpdatedAt = DateTimeOffset.UtcNow;
    }
}
