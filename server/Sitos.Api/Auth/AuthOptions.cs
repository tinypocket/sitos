namespace Sitos.Api.Auth;

/// <summary>
/// OIDC bearer-token validation settings. Deliberately provider-agnostic — point Authority and
/// Audience at any OIDC issuer and the API validates its tokens. When unset, the app falls back
/// to the M1 dev user so local development needs no identity provider.
///
/// Google:  Authority = https://accounts.google.com,  Audience = your Google OAuth *web* client id.
/// Entra:   Authority = https://&lt;tenant&gt;.ciamlogin.com/&lt;tenant-id&gt;/v2.0,  Audience = the API app id.
/// </summary>
public class AuthOptions
{
    public const string Section = "Auth";

    public string? Authority { get; set; }
    public string? Audience { get; set; }

    public bool IsConfigured => !string.IsNullOrWhiteSpace(Authority) && !string.IsNullOrWhiteSpace(Audience);

    /// <summary>
    /// Dev/staging only: accept <see cref="TestToken"/> as a valid bearer token, mapped to a fixed
    /// test user, so features can be exercised without interactive sign-in. NEVER enable in prod —
    /// it is additionally refused when Sitos:Environment is "prod".
    /// </summary>
    public bool AllowTestToken { get; set; }
    public string? TestToken { get; set; }
}
