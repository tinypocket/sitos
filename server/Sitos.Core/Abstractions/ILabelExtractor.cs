using Sitos.Core;

namespace Sitos.Core.Abstractions;

/// <summary>
/// Reads a Nutrition Facts label photo into structured, per-serving nutrition via a vision model.
/// Mirrors the external-provider pattern: a typed HttpClient calls the model's HTTP API directly.
/// </summary>
public interface ILabelExtractor
{
    /// <summary>
    /// True when the underlying vision API is configured (API key present). When false, callers
    /// should surface a 503 rather than attempting a call.
    /// </summary>
    bool IsConfigured { get; }

    /// <summary>
    /// Extract per-serving nutrition from a base64-encoded label image.
    /// </summary>
    /// <param name="imageBase64">Base64 of the label photo (no data: prefix).</param>
    /// <param name="mimeType">Image MIME type, e.g. <c>image/jpeg</c>.</param>
    /// <exception cref="LabelExtractionException">The model call failed or returned no usable result.</exception>
    Task<LabelExtractionResult> ExtractAsync(string imageBase64, string mimeType, CancellationToken ct = default);
}
