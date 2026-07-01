using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Sitos.Core;
using Sitos.Core.Abstractions;
using Sitos.Infrastructure.Providers;

namespace Sitos.Infrastructure.Services;

/// <summary>
/// Parses a meal photo into detected foods/dishes via the Anthropic Messages API. Calls the HTTP
/// API directly through a typed <see cref="HttpClient"/> (mirroring <see cref="AnthropicLabelExtractor"/>
/// — no SDK). Structured output is forced via a single tool (<c>report_meal</c>) with <c>tool_choice</c>,
/// so the model's reply is a tool_use block whose input matches the response contract exactly.
/// </summary>
public class AnthropicMealPhotoParser(
    HttpClient http,
    IOptions<AnthropicOptions> options,
    ILogger<AnthropicMealPhotoParser> logger) : IMealPhotoParser
{
    private readonly AnthropicOptions _opt = options.Value;

    private const string ToolName = "report_meal";

    public bool IsConfigured => !string.IsNullOrWhiteSpace(_opt.ApiKey);

    private static readonly string[] ConfidenceValues =
        [MealConfidence.Verified, MealConfidence.Estimated, MealConfidence.CheckThis];

    private const string BreakdownInstruction =
        "Look at this meal photo. Identify EACH distinct food or ingredient on the plate. Call the " +
        "report_meal tool with one entry per food in the 'items' array. For each entry, estimate the " +
        "portion in grams and the calories and macros (protein, carbs, fat in grams) FOR THAT PORTION " +
        "(not per-100g). Set confidence to 'verified' only if you are highly certain, otherwise " +
        "'estimated' (most items should be 'estimated'), or 'checkThis' when the food or portion is " +
        "hard to judge. Leave caloriesMin and caloriesMax null in this mode. If the image contains no " +
        "food, return an empty 'items' list. " +
        "Separately, fill the 'suggestions' array with plausible-but-uncertain ingredients you did NOT " +
        "include in 'items' — things that might be in the dish but you are not sure about (e.g. a hidden " +
        "sauce, cooking oil or butter, a garnish, dressing, or a likely side). Use the same entry shape, " +
        "with grams/calories/macros for the likely portion. Only include genuinely plausible items, at " +
        "most 5, and never duplicate anything already in 'items'. Use 'checkThis' confidence for these. " +
        "If you have no real suggestions, return an empty 'suggestions' list. " +
        "For EVERY entry (in both 'items' and 'suggestions'), also fill its 'alternates' array with 2-3 " +
        "alternative food names the user might have instead of the one you named — plausible swaps for the " +
        "same item (e.g. 'grilled chicken breast' → 'fried chicken breast', 'rotisserie chicken', " +
        "'chicken thigh'). Keep them short, no duplicates, and never repeat the entry's own name.";

    private const string EstimateInstruction =
        "Look at this meal photo and treat the whole plate as ONE dish. Call the report_meal tool with " +
        "EXACTLY ONE entry in the 'items' array: a short name for the dish, the total estimated portion " +
        "in grams, and the total estimated calories and macros (protein, carbs, fat in grams). Also set " +
        "caloriesMin and caloriesMax to a realistic low/high band for the total calories. Set confidence " +
        "to 'estimated'. Also fill that entry's 'alternates' array with 2-3 alternative whole-dish guesses " +
        "— other dishes the plate could plausibly be (e.g. 'chicken alfredo' → 'chicken parmesan pasta', " +
        "'fettuccine carbonara'). Keep them short, no duplicates, and never repeat the dish's own name. " +
        "Leave the 'suggestions' array empty in this mode. If the image contains no food, " +
        "return an empty 'items' list.";

    public async Task<MealParseResult> ParseAsync(
        string imageBase64, string mimeType, string mode, CancellationToken ct = default)
    {
        if (!IsConfigured)
            throw new MealPhotoParseException("Anthropic API key not configured");

        var estimate = string.Equals(mode, MealParseMode.Estimate, StringComparison.OrdinalIgnoreCase);
        var body = BuildRequestBody(imageBase64, mimeType, estimate);
        var json = JsonSerializer.Serialize(body);

        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Post, $"{_opt.BaseUrl}/v1/messages")
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json")
            };
            req.Headers.TryAddWithoutValidation("x-api-key", _opt.ApiKey);
            req.Headers.TryAddWithoutValidation("anthropic-version", _opt.ApiVersion);

            using var resp = await http.SendAsync(req, ct);
            var respBody = await resp.Content.ReadAsStringAsync(ct);

            if (!resp.IsSuccessStatusCode)
            {
                logger.LogWarning("Anthropic meal-photo parse returned {Status}: {Body}",
                    (int)resp.StatusCode, Truncate(respBody));
                throw new MealPhotoParseException($"Vision model returned status {(int)resp.StatusCode}.");
            }

            return ParseResponse(respBody, estimate);
        }
        catch (MealPhotoParseException)
        {
            throw;
        }
        catch (Exception ex) when (!ct.IsCancellationRequested) // timeouts surface as TaskCanceled
        {
            logger.LogWarning(ex, "Anthropic meal-photo parse call failed");
            throw new MealPhotoParseException("Could not reach the vision model.");
        }
    }

    private object BuildRequestBody(string imageBase64, string mimeType, bool estimate) => new
    {
        model = _opt.Model,
        max_tokens = _opt.MaxTokens,
        tools = new[]
        {
            new
            {
                name = ToolName,
                description = "Report the foods/dishes detected in a meal photo with estimated portions and nutrition.",
                input_schema = BuildInputSchema()
            }
        },
        tool_choice = new { type = "tool", name = ToolName },
        messages = new[]
        {
            new
            {
                role = "user",
                content = new object[]
                {
                    new
                    {
                        type = "image",
                        source = new { type = "base64", media_type = mimeType, data = imageBase64 }
                    },
                    new { type = "text", text = estimate ? EstimateInstruction : BreakdownInstruction }
                }
            }
        }
    };

    private static object BuildInputSchema() => new
    {
        type = "object",
        properties = new
        {
            items = new
            {
                type = "array",
                description = "One entry per detected food/dish. Empty when no food is present.",
                items = BuildItemSchema()
            },
            suggestions = new
            {
                type = "array",
                description = "Lower-confidence 'maybe' ingredients NOT in 'items' (e.g. a hidden sauce, " +
                    "oil, garnish, or likely side). At most 5, no duplicates of 'items'. Empty when none " +
                    "(always empty in estimate mode).",
                items = BuildItemSchema()
            }
        },
        required = new[] { "items", "suggestions" },
        additionalProperties = false
    };

    private static object BuildItemSchema() => new
    {
        type = "object",
        properties = new
        {
            name = new { type = "string", description = "Short name of the food or dish." },
            grams = new { type = "number", description = "Estimated portion weight in grams." },
            calories = new { type = "number", description = "Estimated calories for this portion." },
            protein = new { type = "number", description = "Grams of protein for this portion." },
            carbs = new { type = "number", description = "Grams of carbohydrate for this portion." },
            fat = new { type = "number", description = "Grams of fat for this portion." },
            confidence = new { type = "string", @enum = ConfidenceValues },
            caloriesMin = new { type = new[] { "number", "null" }, description = "Low end of the calorie range (estimate mode only)." },
            caloriesMax = new { type = new[] { "number", "null" }, description = "High end of the calorie range (estimate mode only)." },
            alternates = new
            {
                type = "array",
                description = "2-3 alternative food names the user could swap this entry to (plausible " +
                    "swaps for the same item, or alternative whole-dish guesses in estimate mode). Short, " +
                    "no duplicates, never repeating this entry's own name.",
                items = new { type = "string" }
            }
        },
        required = new[] { "name", "grams", "calories", "protein", "carbs", "fat", "confidence", "caloriesMin", "caloriesMax", "alternates" },
        additionalProperties = false
    };

    private MealParseResult ParseResponse(string respBody, bool estimate)
    {
        using var doc = JsonDocument.Parse(respBody);
        var root = doc.RootElement;

        if (!root.TryGetProperty("content", out var content) || content.ValueKind != JsonValueKind.Array)
            throw new MealPhotoParseException("Vision model returned no content.");

        foreach (var block in content.EnumerateArray())
        {
            if (block.TryGetProperty("type", out var t) && t.GetString() == "tool_use" &&
                block.TryGetProperty("name", out var n) && n.GetString() == ToolName &&
                block.TryGetProperty("input", out var input) && input.ValueKind == JsonValueKind.Object)
            {
                var items = ReadItems(input, "items", estimate);

                // Estimate mode is contractually a single dish row; keep only the first if over-returned.
                if (estimate && items.Count > 1)
                    items = items.GetRange(0, 1);

                // Suggestions are breakdown-only "maybe" extras and never carry a calorie range.
                var suggestions = estimate
                    ? new List<DetectedFoodItem>()
                    : ReadItems(input, "suggestions", estimate: false);

                return new MealParseResult(items, suggestions);
            }
        }

        throw new MealPhotoParseException("Vision model did not return structured meal data.");
    }

    /// <summary>Read a named array of detected items from the tool input. Calorie ranges are only
    /// read in estimate mode (suggestions always pass <paramref name="estimate"/> false).</summary>
    private static List<DetectedFoodItem> ReadItems(JsonElement input, string property, bool estimate)
    {
        var items = new List<DetectedFoodItem>();
        if (!input.TryGetProperty(property, out var arr) || arr.ValueKind != JsonValueKind.Array)
            return items;

        foreach (var el in arr.EnumerateArray())
        {
            if (el.ValueKind != JsonValueKind.Object) continue;

            var name = ReadString(el, "name");
            if (string.IsNullOrWhiteSpace(name)) continue;

            items.Add(new DetectedFoodItem(
                name.Trim(),
                ReadNumber(el, "grams") ?? 0,
                ReadNumber(el, "calories") ?? 0,
                ReadNumber(el, "protein") ?? 0,
                ReadNumber(el, "carbs") ?? 0,
                ReadNumber(el, "fat") ?? 0,
                ResolveConfidence(el),
                estimate ? ReadNumber(el, "caloriesMin") : null,
                estimate ? ReadNumber(el, "caloriesMax") : null,
                ReadAlternates(el, name.Trim())));
        }

        return items;
    }

    /// <summary>Read an item's 'alternates' array of alternative food names, trimmed and de-duplicated
    /// (case-insensitively) and never repeating the entry's own <paramref name="ownName"/>.</summary>
    private static List<string> ReadAlternates(JsonElement el, string ownName)
    {
        var alternates = new List<string>();
        if (!el.TryGetProperty("alternates", out var arr) || arr.ValueKind != JsonValueKind.Array)
            return alternates;

        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { ownName };
        foreach (var a in arr.EnumerateArray())
        {
            if (a.ValueKind != JsonValueKind.String) continue;
            var name = a.GetString()?.Trim();
            if (string.IsNullOrWhiteSpace(name) || !seen.Add(name)) continue;
            alternates.Add(name);
        }

        return alternates;
    }

    private static string? ReadString(JsonElement el, string prop) =>
        el.TryGetProperty(prop, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    private static double? ReadNumber(JsonElement el, string prop)
    {
        if (!el.TryGetProperty(prop, out var v)) return null;
        if (v.ValueKind == JsonValueKind.Number && v.TryGetDouble(out var d)) return d;
        if (v.ValueKind == JsonValueKind.String && double.TryParse(v.GetString(), out var ds)) return ds;
        return null;
    }

    /// <summary>Coerce the model's confidence to a valid value, defaulting to "estimated".</summary>
    private static string ResolveConfidence(JsonElement el)
    {
        var raw = el.TryGetProperty("confidence", out var c) && c.ValueKind == JsonValueKind.String
            ? c.GetString()
            : null;

        return raw switch
        {
            MealConfidence.Verified => MealConfidence.Verified,
            MealConfidence.CheckThis => MealConfidence.CheckThis,
            _ => MealConfidence.Estimated
        };
    }

    private static string Truncate(string s) => s.Length <= 500 ? s : s[..500];
}
