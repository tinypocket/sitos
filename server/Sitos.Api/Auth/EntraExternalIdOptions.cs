namespace Sitos.Api.Auth;

/// <summary>
/// Microsoft Entra External ID (CIAM) settings. When <see cref="Authority"/> is configured, the
/// API validates bearer tokens against Entra and resolves the caller from token claims; otherwise
/// the app falls back to the M1 dev user so local development needs no tenant.
/// </summary>
public class EntraExternalIdOptions
{
    public const string Section = "EntraExternalId";

    /// <summary>
    /// OIDC authority, e.g. <c>https://&lt;tenant&gt;.ciamlogin.com/&lt;tenant-id&gt;/v2.0</c>.
    /// </summary>
    public string? Authority { get; set; }

    /// <summary>The API app registration's audience (its client/app id, or <c>api://&lt;id&gt;</c>).</summary>
    public string? Audience { get; set; }

    public bool IsConfigured => !string.IsNullOrWhiteSpace(Authority) && !string.IsNullOrWhiteSpace(Audience);
}
