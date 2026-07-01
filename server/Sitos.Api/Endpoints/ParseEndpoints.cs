using Sitos.Api.Auth;
using Sitos.Api.Contracts;
using Sitos.Core;
using Sitos.Core.Abstractions;
using Sitos.Core.Entities;

namespace Sitos.Api.Endpoints;

public static class ParseEndpoints
{
    public static IEndpointRouteBuilder MapParseEndpoints(this IEndpointRouteBuilder app, bool requireAuth = false)
    {
        var group = app.MapGroup("/api/parse").WithTags("Parse");
        if (requireAuth) group.RequireAuthorization();

        // Meal-photo parsing via Claude vision. Detects foods/dishes with estimated portions and
        // nutrition, then resolves each to a loggable Food (existing match, else a persisted estimated
        // food) so the client can commit rows through the normal diary flow. Image is transient.
        group.MapPost("/photo", async (
            ParsePhotoRequest req,
            IMealPhotoParser parser,
            IFoodService foods,
            ICurrentUser user,
            CancellationToken ct) =>
        {
            if (!parser.IsConfigured)
                return Results.Json(new { error = "Anthropic API key not configured" }, statusCode: 503);

            if (string.IsNullOrWhiteSpace(req.ImageBase64))
                return Results.BadRequest("imageBase64 is required.");

            var mimeType = string.IsNullOrWhiteSpace(req.MimeType) ? "image/jpeg" : req.MimeType.Trim();

            // Default to breakdown; accept estimate; reject anything else so typos surface.
            var mode = string.IsNullOrWhiteSpace(req.Mode)
                ? MealParseMode.Breakdown
                : req.Mode.Trim().ToLowerInvariant();
            if (mode != MealParseMode.Breakdown && mode != MealParseMode.Estimate)
                return Results.BadRequest("mode must be 'breakdown' or 'estimate'.");

            try
            {
                var result = await parser.ParseAsync(req.ImageBase64, mimeType, mode, ct);

                // Resolve confident items and lower-confidence "maybe" suggestions through the exact
                // same search-or-create path; suggestions are a parallel, separate list in the response.
                var rows = await ResolveRowsAsync(result.Items, foods, user, ct);
                var suggestions = await ResolveRowsAsync(result.Suggestions, foods, user, ct);

                return Results.Ok(new ParsePhotoResponse(rows, suggestions));
            }
            catch (MealPhotoParseException ex)
            {
                return Results.Json(new { error = ex.Message }, statusCode: 502);
            }
        })
        .WithName("ParseMealPhoto")
        .WithSummary("Detect foods in a meal photo and resolve each to a loggable food (Claude vision).");

        return app;
    }

    /// <summary>
    /// Resolve a list of detected items to response rows: each is resolved to a loggable Food via the
    /// same search-or-create path, with calories kept consistent with what the client will log. Items
    /// with grams ≤ 0 are skipped (no positive weight to derive per-100g nutrition). Used for both the
    /// confident <c>rows</c> and the lower-confidence <c>suggestions</c>.
    /// </summary>
    private static async Task<List<ParsedRowDto>> ResolveRowsAsync(
        IReadOnlyList<DetectedFoodItem> items,
        IFoodService foods,
        ICurrentUser user,
        CancellationToken ct)
    {
        var rows = new List<ParsedRowDto>();

        foreach (var item in items)
        {
            // Need a positive weight to derive per-100g nutrition for a loggable food.
            if (item.Grams <= 0) continue;

            var food = await ResolveFoodAsync(item, foods, user, ct);
            if (food is null) continue;

            // Keep the row's calories consistent with what the client will actually log
            // (food's per-100g × grams). For a freshly created estimated food this equals the
            // AI's per-portion estimate exactly; for a matched food it uses the matched nutrition.
            var calories = Math.Round(food.CaloriesPer100g * item.Grams / 100d, 0);

            double[]? range = item.CaloriesMin is double mn && item.CaloriesMax is double mx
                ? [Math.Round(mn, 0), Math.Round(mx, 0)]
                : null;

            var alternates = await ResolveAlternatesAsync(item, foods, user, ct);

            rows.Add(new ParsedRowDto(
                FoodDto.From(food),
                Math.Round(item.Grams, 0),
                calories,
                item.Confidence,
                range,
                alternates));
        }

        return rows;
    }

    /// <summary>
    /// Resolve an item's alternate NAMES to loggable Foods via the exact same search-or-create path as
    /// the main food. Each alternate reuses the item's grams/macros so a freshly created estimated food
    /// gets sane per-100g nutrition. Returns the resolved Food DTOs only (not full rows); always non-null.
    /// </summary>
    private static async Task<List<FoodDto>> ResolveAlternatesAsync(
        DetectedFoodItem item,
        IFoodService foods,
        ICurrentUser user,
        CancellationToken ct)
    {
        var alternates = new List<FoodDto>();
        if (item.Alternates.Count == 0 || item.Grams <= 0) return alternates;

        // Alternates are lightweight swap options. Create estimated foods directly
        // from the item's macros — deliberately SKIPPING the external provider search
        // (SearchAsync) that ResolveFoodAsync does, since running it per-alternate is
        // what pushed a multi-item meal past the client's request timeout.
        var grams = item.Grams;
        var userId = await user.GetUserIdAsync(ct);
        foreach (var name in item.Alternates)
        {
            if (string.IsNullOrWhiteSpace(name)) continue;
            var food = new Food
            {
                Name = name.Trim(),
                ServingSizeGrams = grams,
                CaloriesPer100g = item.Calories * 100d / grams,
                ProteinPer100g = item.Protein * 100d / grams,
                CarbsPer100g = item.Carbs * 100d / grams,
                FatPer100g = item.Fat * 100d / grams
            };
            var saved = await foods.AddUserFoodAsync(food, userId, ct);
            if (saved is not null) alternates.Add(FoodDto.From(saved));
        }

        return alternates;
    }

    /// <summary>
    /// Resolve a detected item to a persisted Food: reuse an existing food on a confident name match,
    /// otherwise create+persist an estimated food from the AI numbers (caloriesPer100g = perPortion×100/grams).
    /// </summary>
    private static async Task<Food?> ResolveFoodAsync(
        DetectedFoodItem item,
        IFoodService foods,
        ICurrentUser user,
        CancellationToken ct)
    {
        var matches = await foods.SearchAsync(item.Name, ct);
        var match = PickMatch(matches, item.Name);
        if (match is not null) return match;

        var grams = item.Grams; // caller guarantees > 0
        var userId = await user.GetUserIdAsync(ct);
        var food = new Food
        {
            Name = item.Name,
            ServingSizeGrams = grams,
            CaloriesPer100g = item.Calories * 100d / grams,
            ProteinPer100g = item.Protein * 100d / grams,
            CarbsPer100g = item.Carbs * 100d / grams,
            FatPer100g = item.Fat * 100d / grams
        };
        return await foods.AddUserFoodAsync(food, userId, ct);
    }

    /// <summary>
    /// Pick a "solid" existing match for a detected name: an exact normalized-name equality among the
    /// search results. Kept deliberately conservative so meal estimates aren't logged against an
    /// unrelated database food; everything else falls through to a freshly created estimated food.
    /// </summary>
    private static Food? PickMatch(IReadOnlyList<Food> results, string name)
    {
        var target = Normalize(name);
        if (target.Length == 0) return null;
        return results.FirstOrDefault(f => Normalize(f.Name) == target);
    }

    private static string Normalize(string s)
    {
        Span<char> buf = stackalloc char[s.Length];
        var len = 0;
        foreach (var ch in s)
            if (char.IsLetterOrDigit(ch)) buf[len++] = char.ToLowerInvariant(ch);
        return new string(buf[..len]);
    }
}
