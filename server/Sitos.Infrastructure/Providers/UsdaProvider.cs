using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Sitos.Core;
using Sitos.Core.Abstractions;
using Sitos.Core.Entities;

namespace Sitos.Infrastructure.Providers;

/// <summary>
/// Fallback provider. USDA FoodData Central is strong on whole/unbranded foods. Requires a
/// free API key; when none is configured the provider is a no-op so the app still runs.
/// </summary>
public class UsdaProvider(
    HttpClient http,
    IOptions<UsdaOptions> options,
    ILogger<UsdaProvider> logger) : IFoodProvider
{
    private readonly UsdaOptions _opt = options.Value;

    // USDA FDC nutrient numbers.
    private const int EnergyKcal = 1008;
    private const int Protein = 1003;
    private const int Carbs = 1005;
    private const int Fat = 1004;

    public FoodSource Source => FoodSource.Usda;

    private bool Enabled => !string.IsNullOrWhiteSpace(_opt.ApiKey);

    public async Task<Food?> FindByBarcodeAsync(string barcode, CancellationToken ct = default)
    {
        if (!Enabled) return null;
        // USDA has no direct barcode endpoint; search and match on gtinUpc.
        var foods = await SearchRawAsync(barcode, ct);
        foreach (var food in foods.EnumerateArray())
        {
            if (GetString(food, "gtinUpc")?.TrimStart('0') == barcode.TrimStart('0'))
                return MapFood(food, barcode);
        }
        return null;
    }

    public async Task<IReadOnlyList<Food>> SearchAsync(string query, CancellationToken ct = default)
    {
        if (!Enabled) return [];
        var foods = await SearchRawAsync(query, ct);
        var results = new List<Food>();
        foreach (var food in foods.EnumerateArray())
        {
            var mapped = MapFood(food, GetString(food, "gtinUpc"));
            if (mapped is not null && mapped.CaloriesPer100g > 0) results.Add(mapped);
        }
        return results;
    }

    private async Task<JsonElement> SearchRawAsync(string query, CancellationToken ct)
    {
        var url = $"{_opt.BaseUrl}/foods/search?query={Uri.EscapeDataString(query)}" +
                  $"&pageSize=20&api_key={_opt.ApiKey}";
        try
        {
            using var resp = await http.GetAsync(url, ct);
            if (!resp.IsSuccessStatusCode) return default;

            await using var stream = await resp.Content.ReadAsStreamAsync(ct);
            using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct);
            if (doc.RootElement.TryGetProperty("foods", out var foods))
                return foods.Clone(); // clone so it survives doc disposal
            return default;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "USDA search failed for {Query}", query);
            return default;
        }
    }

    private static Food? MapFood(JsonElement food, string? barcode)
    {
        var name = GetString(food, "description");
        if (string.IsNullOrWhiteSpace(name)) return null;

        double Nutrient(int id)
        {
            if (!food.TryGetProperty("foodNutrients", out var nutrients)) return 0;
            foreach (var nutrient in nutrients.EnumerateArray())
            {
                if (nutrient.TryGetProperty("nutrientId", out var nid) && nid.GetInt32() == id &&
                    nutrient.TryGetProperty("value", out var val) && val.ValueKind == JsonValueKind.Number)
                    return val.GetDouble();
            }
            return 0;
        }

        return new Food
        {
            Barcode = string.IsNullOrWhiteSpace(barcode) ? null : barcode,
            Name = name!.Trim(),
            Brand = GetString(food, "brandOwner") ?? GetString(food, "brandName"),
            CaloriesPer100g = Nutrient(EnergyKcal),
            ProteinPer100g = Nutrient(Protein),
            CarbsPer100g = Nutrient(Carbs),
            FatPer100g = Nutrient(Fat),
            Source = FoodSource.Usda,
            SourceId = food.TryGetProperty("fdcId", out var id) ? id.ToString() : null,
            RawJson = food.GetRawText(),
            VerifiedStatus = VerifiedStatus.OfficialSource
        };
    }

    private static string? GetString(JsonElement el, string prop) =>
        el.ValueKind == JsonValueKind.Object && el.TryGetProperty(prop, out var v) && v.ValueKind == JsonValueKind.String
            ? v.GetString() : null;
}
