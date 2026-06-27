using Microsoft.EntityFrameworkCore;
using Sitos.Api.Auth;
using Sitos.Api.Contracts;
using Sitos.Core.Abstractions;
using Sitos.Infrastructure;

namespace Sitos.Api.Endpoints;

public static class RecipeEndpoints
{
    public static IEndpointRouteBuilder MapRecipeEndpoints(this IEndpointRouteBuilder app, bool requireAuth = false)
    {
        var group = app.MapGroup("/api/recipes").WithTags("Recipes");
        if (requireAuth) group.RequireAuthorization();

        // List the caller's recipes with per-serving nutrition.
        group.MapGet("", async (SitosDbContext db, ICurrentUser user, CancellationToken ct) =>
        {
            var userId = await user.GetUserIdAsync(ct);
            var recipes = await db.Recipes
                .Where(r => r.UserId == userId)
                .Include(r => r.Ingredients).ThenInclude(i => i.Food)
                .OrderBy(r => r.Name)
                .ToListAsync(ct);
            return Results.Ok(recipes.Select(RecipeDto.From));
        }).WithName("GetRecipes");

        group.MapGet("/{id:guid}", async (
            Guid id, SitosDbContext db, ICurrentUser user, CancellationToken ct) =>
        {
            var userId = await user.GetUserIdAsync(ct);
            var recipe = await db.Recipes
                .Where(r => r.Id == id && r.UserId == userId)
                .Include(r => r.Ingredients).ThenInclude(i => i.Food)
                .FirstOrDefaultAsync(ct);
            return recipe is null ? Results.NotFound() : Results.Ok(RecipeDto.From(recipe));
        }).WithName("GetRecipe");

        group.MapPost("", async (
            CreateRecipeRequest req, IRecipeService recipes, SitosDbContext db,
            ICurrentUser user, CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(req.Name)) return Results.BadRequest("Name is required.");
            if (req.Ingredients.Count == 0) return Results.BadRequest("At least one ingredient is required.");

            var userId = await user.GetUserIdAsync(ct);
            var recipe = await recipes.CreateAsync(userId, ToInput(req), ct);
            var dto = await LoadDtoAsync(db, recipe.Id, ct);
            return Results.Created($"/api/recipes/{recipe.Id}", dto);
        }).WithName("CreateRecipe");

        group.MapPut("/{id:guid}", async (
            Guid id, CreateRecipeRequest req, IRecipeService recipes, SitosDbContext db,
            ICurrentUser user, CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(req.Name)) return Results.BadRequest("Name is required.");
            var userId = await user.GetUserIdAsync(ct);
            var updated = await recipes.UpdateAsync(userId, id, ToInput(req), ct);
            if (updated is null) return Results.NotFound();
            return Results.Ok(await LoadDtoAsync(db, id, ct));
        }).WithName("UpdateRecipe");

        group.MapDelete("/{id:guid}", async (
            Guid id, IRecipeService recipes, ICurrentUser user, CancellationToken ct) =>
        {
            var userId = await user.GetUserIdAsync(ct);
            return await recipes.DeleteAsync(userId, id, ct) ? Results.NoContent() : Results.NotFound();
        }).WithName("DeleteRecipe");

        // Log servings of a recipe to a diary meal.
        group.MapPost("/{id:guid}/log", async (
            Guid id, LogRecipeRequest req, IRecipeService recipes, ICurrentUser user, CancellationToken ct) =>
        {
            var userId = await user.GetUserIdAsync(ct);
            var entry = await recipes.LogAsync(userId, id, req.Date, req.Meal, req.Servings, ct);
            return entry is null ? Results.NotFound() : Results.Ok(DiaryEntryDto.From(entry));
        }).WithName("LogRecipe").WithSummary("Log N servings of a recipe to the diary.");

        return app;
    }

    private static RecipeInput ToInput(CreateRecipeRequest req) => new(
        req.Name, req.Servings,
        req.Ingredients.Select(i => new IngredientInput(i.FoodId, i.Quantity, i.Unit)).ToList());

    private static async Task<RecipeDto> LoadDtoAsync(SitosDbContext db, Guid id, CancellationToken ct)
    {
        var recipe = await db.Recipes
            .Where(r => r.Id == id)
            .Include(r => r.Ingredients).ThenInclude(i => i.Food)
            .FirstAsync(ct);
        return RecipeDto.From(recipe);
    }
}
