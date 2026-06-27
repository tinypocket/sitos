using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;

namespace Sitos.Api.Auth;

/// <summary>
/// Dev/staging-only authentication: a single configured bearer token (<c>Auth:TestToken</c>) is
/// accepted and mapped to a fixed "Test User", so the app's features can be exercised on an
/// emulator without interactive Google sign-in. Wired up only when <c>Auth:AllowTestToken</c> is
/// true and the environment is not prod (see Program.cs).
/// </summary>
public class TestAuthHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder,
    IOptions<AuthOptions> auth)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string SchemeName = "TestAuth";

    private readonly string _expected = auth.Value.TestToken ?? string.Empty;

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var header = Request.Headers.Authorization.ToString();
        if (string.IsNullOrEmpty(_expected) || header != $"Bearer {_expected}")
            return Task.FromResult(AuthenticateResult.Fail("Invalid test token"));

        // Stable synthetic identity; OidcCurrentUser provisions a real User row from these claims.
        var claims = new[]
        {
            new Claim("sub", "test-user"),
            new Claim("email", "test@sitos.local"),
            new Claim("name", "Test User"),
        };
        var principal = new ClaimsPrincipal(new ClaimsIdentity(claims, SchemeName));
        return Task.FromResult(AuthenticateResult.Success(
            new AuthenticationTicket(principal, SchemeName)));
    }
}
