namespace Sitos.Core.Abstractions;

/// <summary>
/// Parses a meal photo into detected foods/dishes via a vision model. Mirrors the
/// <see cref="ILabelExtractor"/> pattern: a typed HttpClient calls the model's HTTP API directly.
/// </summary>
public interface IMealPhotoParser
{
    /// <summary>
    /// True when the underlying vision API is configured (API key present). When false, callers
    /// should surface a 503 rather than attempting a call.
    /// </summary>
    bool IsConfigured { get; }

    /// <summary>
    /// Detect the foods/dishes in a base64-encoded meal photo.
    /// </summary>
    /// <param name="imageBase64">Base64 of the meal photo (no data: prefix).</param>
    /// <param name="mimeType">Image MIME type, e.g. <c>image/jpeg</c>.</param>
    /// <param name="mode"><see cref="MealParseMode.Breakdown"/> or <see cref="MealParseMode.Estimate"/>.</param>
    /// <exception cref="MealPhotoParseException">The model call failed or returned no usable result.</exception>
    Task<MealParseResult> ParseAsync(
        string imageBase64, string mimeType, string mode, CancellationToken ct = default);
}
