namespace Sitos.Core;

/// <summary>
/// Result of reading a Nutrition Facts label photo. Every field is reported with the value as
/// printed for ONE serving (per-serving, not per-100g) plus a confidence: <c>verified</c> when
/// read clearly, <c>estimated</c> when inferred/uncertain, <c>unread</c> (value null) when absent.
/// Serialized to the wire shape the Flutter client expects (each field is { value, confidence }).
/// </summary>
public sealed record LabelExtractionResult(
    LabelTextField Name,
    LabelTextField Brand,
    LabelTextField ServingSizeLabel,
    LabelNumberField ServingSizeGrams,
    LabelNumberField Calories,
    LabelNumberField Protein,
    LabelNumberField Carbs,
    LabelNumberField Fat);

/// <summary>A text-valued label field. <see cref="Value"/> is null when <see cref="Confidence"/> is unread.</summary>
public sealed record LabelTextField(string? Value, string Confidence);

/// <summary>A numeric (per-serving) label field. <see cref="Value"/> is null when <see cref="Confidence"/> is unread.</summary>
public sealed record LabelNumberField(double? Value, string Confidence);

/// <summary>Confidence levels for an extracted field. Wire values are the lowercase names.</summary>
public static class LabelConfidence
{
    public const string Verified = "verified";
    public const string Estimated = "estimated";
    public const string Unread = "unread";
}

/// <summary>Raised when the vision model call fails or returns an unusable response.</summary>
public sealed class LabelExtractionException(string message) : Exception(message);
