using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Sitos.Core;
using Sitos.Core.Abstractions;
using Sitos.Infrastructure.Providers;

namespace Sitos.Infrastructure.Services;

/// <summary>
/// Reads a Nutrition Facts label photo via the Anthropic Messages API. Calls the HTTP API
/// directly through a typed <see cref="HttpClient"/> (mirroring the food-provider pattern — no SDK).
/// Structured output is forced via a single tool (<c>report_nutrition</c>) with <c>tool_choice</c>,
/// so the model's reply is a tool_use block whose input matches the response contract exactly.
/// </summary>
public class AnthropicLabelExtractor(
    HttpClient http,
    IOptions<AnthropicOptions> options,
    ILogger<AnthropicLabelExtractor> logger) : ILabelExtractor
{
    private readonly AnthropicOptions _opt = options.Value;

    private const string ToolName = "report_nutrition";

    public bool IsConfigured => !string.IsNullOrWhiteSpace(_opt.ApiKey);

    private static readonly string[] ConfidenceValues = ["verified", "estimated", "unread"];

    private const string Instruction =
        "Read this Nutrition Facts label photo. Report the values exactly as printed on the label for " +
        "ONE serving (per-serving amounts, NOT per-100g). Call the report_nutrition tool with one entry " +
        "per field. For each field set confidence: 'verified' when you can read it clearly, 'estimated' " +
        "when you infer or are uncertain (serving size is usually estimated), and 'unread' with a null " +
        "value when the label does not show it. calories/protein/carbs/fat are the per-serving amounts.";

    public async Task<LabelExtractionResult> ExtractAsync(
        string imageBase64, string mimeType, CancellationToken ct = default)
    {
        if (!IsConfigured)
            throw new LabelExtractionException("Anthropic API key not configured");

        var body = BuildRequestBody(imageBase64, mimeType);
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
                logger.LogWarning("Anthropic label extraction returned {Status}: {Body}",
                    (int)resp.StatusCode, Truncate(respBody));
                throw new LabelExtractionException($"Vision model returned status {(int)resp.StatusCode}.");
            }

            return ParseResponse(respBody);
        }
        catch (LabelExtractionException)
        {
            throw;
        }
        catch (Exception ex) when (!ct.IsCancellationRequested) // timeouts surface as TaskCanceled
        {
            logger.LogWarning(ex, "Anthropic label extraction call failed");
            throw new LabelExtractionException("Could not reach the vision model.");
        }
    }

    private object BuildRequestBody(string imageBase64, string mimeType) => new
    {
        model = _opt.Model,
        max_tokens = _opt.MaxTokens,
        tools = new[]
        {
            new
            {
                name = ToolName,
                description = "Report the nutrition facts read from a label photo, per serving.",
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
                    new { type = "text", text = Instruction }
                }
            }
        }
    };

    private static object BuildInputSchema() => new
    {
        type = "object",
        properties = new
        {
            name = TextField("Product name as printed on the package."),
            brand = TextField("Brand or manufacturer name."),
            servingSizeLabel = TextField("Serving size text as printed, e.g. '1 cup (45 g)'."),
            servingSizeGrams = NumberField("Serving size in grams."),
            calories = NumberField("Calories in one serving."),
            protein = NumberField("Grams of protein in one serving."),
            carbs = NumberField("Grams of total carbohydrate in one serving."),
            fat = NumberField("Grams of total fat in one serving.")
        },
        required = new[]
        {
            "name", "brand", "servingSizeLabel", "servingSizeGrams", "calories", "protein", "carbs", "fat"
        },
        additionalProperties = false
    };

    private static object TextField(string description) => new
    {
        type = "object",
        description,
        properties = new
        {
            value = new { type = new[] { "string", "null" } },
            confidence = new { type = "string", @enum = ConfidenceValues }
        },
        required = new[] { "value", "confidence" },
        additionalProperties = false
    };

    private static object NumberField(string description) => new
    {
        type = "object",
        description,
        properties = new
        {
            value = new { type = new[] { "number", "null" } },
            confidence = new { type = "string", @enum = ConfidenceValues }
        },
        required = new[] { "value", "confidence" },
        additionalProperties = false
    };

    private LabelExtractionResult ParseResponse(string respBody)
    {
        using var doc = JsonDocument.Parse(respBody);
        var root = doc.RootElement;

        if (!root.TryGetProperty("content", out var content) || content.ValueKind != JsonValueKind.Array)
            throw new LabelExtractionException("Vision model returned no content.");

        foreach (var block in content.EnumerateArray())
        {
            if (block.TryGetProperty("type", out var t) && t.GetString() == "tool_use" &&
                block.TryGetProperty("name", out var n) && n.GetString() == ToolName &&
                block.TryGetProperty("input", out var input) && input.ValueKind == JsonValueKind.Object)
            {
                return new LabelExtractionResult(
                    ReadText(input, "name"),
                    ReadText(input, "brand"),
                    ReadText(input, "servingSizeLabel"),
                    ReadNumber(input, "servingSizeGrams"),
                    ReadNumber(input, "calories"),
                    ReadNumber(input, "protein"),
                    ReadNumber(input, "carbs"),
                    ReadNumber(input, "fat"));
            }
        }

        throw new LabelExtractionException("Vision model did not return structured nutrition.");
    }

    private static LabelTextField ReadText(JsonElement input, string prop)
    {
        if (!TryField(input, prop, out var field))
            return new LabelTextField(null, LabelConfidence.Unread);

        string? value = field.TryGetProperty("value", out var v) && v.ValueKind == JsonValueKind.String
            ? v.GetString()
            : null;
        return new LabelTextField(value, ResolveConfidence(field, value is null));
    }

    private static LabelNumberField ReadNumber(JsonElement input, string prop)
    {
        if (!TryField(input, prop, out var field))
            return new LabelNumberField(null, LabelConfidence.Unread);

        double? value = null;
        if (field.TryGetProperty("value", out var v))
        {
            if (v.ValueKind == JsonValueKind.Number && v.TryGetDouble(out var d)) value = d;
            else if (v.ValueKind == JsonValueKind.String && double.TryParse(v.GetString(), out var ds)) value = ds;
        }
        return new LabelNumberField(value, ResolveConfidence(field, value is null));
    }

    private static bool TryField(JsonElement input, string prop, out JsonElement field) =>
        input.TryGetProperty(prop, out field) && field.ValueKind == JsonValueKind.Object;

    /// <summary>Coerce the model's confidence to a valid value: null values are always "unread".</summary>
    private static string ResolveConfidence(JsonElement field, bool valueMissing)
    {
        if (valueMissing) return LabelConfidence.Unread;

        var raw = field.TryGetProperty("confidence", out var c) && c.ValueKind == JsonValueKind.String
            ? c.GetString()
            : null;

        return raw switch
        {
            LabelConfidence.Verified => LabelConfidence.Verified,
            LabelConfidence.Unread => LabelConfidence.Estimated, // value present but flagged unread → estimated
            _ => LabelConfidence.Estimated
        };
    }

    private static string Truncate(string s) => s.Length <= 500 ? s : s[..500];
}
