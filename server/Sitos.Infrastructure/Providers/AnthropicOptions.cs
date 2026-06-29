namespace Sitos.Infrastructure.Providers;

/// <summary>
/// Configuration for the Anthropic Messages API (used for Nutrition Facts label extraction).
/// The API key is read from <c>Anthropic:ApiKey</c> (env var <c>Anthropic__ApiKey</c>, or
/// user-secrets / Key Vault under the same name). When empty, label extraction returns 503.
/// </summary>
public class AnthropicOptions
{
    public const string Section = "Anthropic";

    /// <summary>Secret API key. Leave unset to disable label extraction (endpoint returns 503).</summary>
    public string? ApiKey { get; set; }

    public string BaseUrl { get; set; } = "https://api.anthropic.com";

    /// <summary>Messages API version header value.</summary>
    public string ApiVersion { get; set; } = "2023-06-01";

    /// <summary>Vision-capable model used to read the label.</summary>
    public string Model { get; set; } = "claude-opus-4-8";

    public int MaxTokens { get; set; } = 1024;
}
