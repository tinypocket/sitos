using Sitos.Api.Auth;
using Sitos.Api.Contracts;
using Sitos.Core.Abstractions;
using Sitos.Core.Entities;

namespace Sitos.Api.Endpoints;

public static class FoodEndpoints
{
    public static IEndpointRouteBuilder MapFoodEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/foods").WithTags("Foods");

        // Barcode lookup — cache-first, provider fallback, auto-cache. This is the core scan call.
        group.MapGet("/barcode/{code}", async (string code, IFoodService foods, CancellationToken ct) =>
        {
            var food = await foods.GetByBarcodeAsync(code, ct);
            return food is null ? Results.NotFound() : Results.Ok(FoodDto.From(food));
        })
        .WithName("GetFoodByBarcode")
        .WithSummary("Look up a food by barcode (cached, with Open Food Facts / USDA fallback).");

        // Free-text search across cache + primary provider.
        group.MapGet("/search", async (string q, IFoodService foods, CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(q)) return Results.BadRequest("Query 'q' is required.");
            var results = await foods.SearchAsync(q, ct);
            return Results.Ok(results.Select(FoodDto.From));
        })
        .WithName("SearchFoods")
        .WithSummary("Search foods by name.");

        // User-contributed custom food.
        group.MapPost("", async (
            CreateUserFoodRequest req, IFoodService foods, ICurrentUser user, CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(req.Name)) return Results.BadRequest("Name is required.");

            var userId = await user.GetUserIdAsync(ct);
            var food = new Food
            {
                Name = req.Name.Trim(),
                Brand = req.Brand,
                Barcode = string.IsNullOrWhiteSpace(req.Barcode) ? null : req.Barcode.Trim(),
                ServingSizeGrams = req.ServingSizeGrams,
                ServingSizeLabel = req.ServingSizeLabel,
                CaloriesPer100g = req.CaloriesPer100g,
                ProteinPer100g = req.ProteinPer100g,
                CarbsPer100g = req.CarbsPer100g,
                FatPer100g = req.FatPer100g
            };
            var saved = await foods.AddUserFoodAsync(food, userId, ct);
            return Results.Created($"/api/foods/{saved.Id}", FoodDto.From(saved));
        })
        .WithName("CreateUserFood")
        .WithSummary("Add a custom food.");

        return app;
    }
}
