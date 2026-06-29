using Sitos.Api.Auth;
using Sitos.Api.Contracts;
using Sitos.Core;
using Sitos.Core.Abstractions;
using Sitos.Core.Entities;

namespace Sitos.Api.Endpoints;

public static class FoodEndpoints
{
    public static IEndpointRouteBuilder MapFoodEndpoints(this IEndpointRouteBuilder app, bool requireAuth = false)
    {
        var group = app.MapGroup("/api/foods").WithTags("Foods");
        if (requireAuth) group.RequireAuthorization();

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

        // Nutrition Facts label extraction via Claude vision. Reads per-serving values off a photo;
        // the client pre-fills the create-food form and the user reviews before saving. The image is
        // processed transiently and never stored.
        group.MapPost("/extract-label", async (
            ExtractLabelRequest req, ILabelExtractor extractor, CancellationToken ct) =>
        {
            if (!extractor.IsConfigured)
                return Results.Json(new { error = "Anthropic API key not configured" }, statusCode: 503);

            if (string.IsNullOrWhiteSpace(req.ImageBase64))
                return Results.BadRequest("imageBase64 is required.");

            var mimeType = string.IsNullOrWhiteSpace(req.MimeType) ? "image/jpeg" : req.MimeType.Trim();

            try
            {
                var result = await extractor.ExtractAsync(req.ImageBase64, mimeType, ct);
                return Results.Ok(result);
            }
            catch (LabelExtractionException ex)
            {
                return Results.Json(new { error = ex.Message }, statusCode: 502);
            }
        })
        .WithName("ExtractLabel")
        .WithSummary("Extract per-serving nutrition from a Nutrition Facts label photo (Claude vision).");

        return app;
    }
}
