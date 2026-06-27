using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Sitos.Core;
using Sitos.Core.Abstractions;
using Sitos.Core.Entities;

namespace Sitos.Infrastructure.Providers;

/// <summary>
/// Primary provider. Open Food Facts is free, requires no auth, and exposes nutriments
/// already normalised to a per-100g basis — which maps directly onto <see cref="Food"/>.
/// </summary>
public class OpenFoodFactsProvider(
    HttpClient http,
    IOptions<OpenFoodFactsOptions> options,
    ILogger<OpenFoodFactsProvider> logger) : IFoodProvider
{
    private readonly OpenFoodFactsOptions _opt = options.Value;

    public FoodSource Source => FoodSource.OpenFoodFacts;

    public async Task<Food?> FindByBarcodeAsync(string barcode, CancellationToken ct = default)
    {
        var url = $"{_opt.BaseUrl}/api/v2/product/{Uri.EscapeDataString(barcode)}.json";
        try
        {
            using var resp = await http.GetAsync(url, ct);
            if (!resp.IsSuccessStatusCode) return null;

            await using var stream = await resp.Content.ReadAsStreamAsync(ct);
            using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct);
            var root = doc.RootElement;

            // status == 1 means the product was found.
            if (!root.TryGetProperty("status", out var status) || status.GetInt32() != 1) return null;
            if (!root.TryGetProperty("product", out var product)) return null;

            return MapProduct(product, barcode);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Open Food Facts barcode lookup failed for {Barcode}", barcode);
            return null;
        }
    }

    public async Task<IReadOnlyList<Food>> SearchAsync(string query, CancellationToken ct = default)
    {
        var url = $"{_opt.BaseUrl}/cgi/search.pl?search_terms={Uri.EscapeDataString(query)}" +
                  "&search_simple=1&action=process&json=1&page_size=20";
        try
        {
            using var resp = await http.GetAsync(url, ct);
            if (!resp.IsSuccessStatusCode) return [];

            await using var stream = await resp.Content.ReadAsStreamAsync(ct);
            using var doc = await JsonDocument.ParseAsync(stream, cancellationToken: ct);

            if (!doc.RootElement.TryGetProperty("products", out var products)) return [];

            var results = new List<Food>();
            foreach (var product in products.EnumerateArray())
            {
                var code = product.TryGetProperty("code", out var c) ? c.GetString() : null;
                var food = MapProduct(product, code);
                if (food is not null && food.CaloriesPer100g > 0) results.Add(food);
            }
            return results;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Open Food Facts search failed for {Query}", query);
            return [];
        }
    }

    private Food? MapProduct(JsonElement product, string? barcode)
    {
        var name = GetString(product, "product_name");
        if (string.IsNullOrWhiteSpace(name)) name = GetString(product, "generic_name");
        if (string.IsNullOrWhiteSpace(name)) return null;

        var nutriments = product.TryGetProperty("nutriments", out var n) ? n : default;

        return new Food
        {
            Barcode = barcode,
            Name = name!.Trim(),
            Brand = GetString(product, "brands"),
            ServingSizeGrams = GetDouble(product, "serving_quantity"),
            ServingSizeLabel = GetString(product, "serving_size"),
            CaloriesPer100g = GetDouble(nutriments, "energy-kcal_100g") ?? 0,
            ProteinPer100g = GetDouble(nutriments, "proteins_100g") ?? 0,
            CarbsPer100g = GetDouble(nutriments, "carbohydrates_100g") ?? 0,
            FatPer100g = GetDouble(nutriments, "fat_100g") ?? 0,
            Source = FoodSource.OpenFoodFacts,
            SourceId = barcode,
            RawJson = product.GetRawText(),
            VerifiedStatus = VerifiedStatus.Unverified
        };
    }

    private static string? GetString(JsonElement el, string prop) =>
        el.ValueKind == JsonValueKind.Object && el.TryGetProperty(prop, out var v) && v.ValueKind == JsonValueKind.String
            ? v.GetString() : null;

    // OFF returns numbers inconsistently as JSON numbers or numeric strings.
    private static double? GetDouble(JsonElement el, string prop)
    {
        if (el.ValueKind != JsonValueKind.Object || !el.TryGetProperty(prop, out var v)) return null;
        return v.ValueKind switch
        {
            JsonValueKind.Number => v.GetDouble(),
            JsonValueKind.String when double.TryParse(v.GetString(), out var d) => d,
            _ => null
        };
    }
}
