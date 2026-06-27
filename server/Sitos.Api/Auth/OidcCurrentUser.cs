using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using Sitos.Core.Entities;
using Sitos.Infrastructure;

namespace Sitos.Api.Auth;

/// <summary>
/// Resolves the caller from the validated OIDC token and provisions a local <see cref="User"/>
/// on first sight (just-in-time), keyed by the token subject. Works for any OIDC provider:
/// Google tokens carry <c>sub</c>/<c>email</c>/<c>name</c>; Entra adds <c>oid</c>. This keeps the
/// database the source of truth for all user-owned data and analytics.
/// </summary>
public class OidcCurrentUser(IHttpContextAccessor accessor, SitosDbContext db) : ICurrentUser
{
    public async Task<Guid> GetUserIdAsync(CancellationToken ct = default)
    {
        var principal = accessor.HttpContext?.User
            ?? throw new InvalidOperationException("No HttpContext for the current request.");

        // 'oid' is Entra's stable object id; 'sub' is the standard OIDC subject (Google uses this).
        var externalId = principal.FindFirstValue("oid")
                         ?? principal.FindFirstValue(ClaimTypes.NameIdentifier)
                         ?? principal.FindFirstValue("sub")
                         ?? throw new UnauthorizedAccessException("Token has no subject claim.");

        var user = await db.Users.FirstOrDefaultAsync(u => u.ExternalId == externalId, ct);
        if (user is not null) return user.Id;

        user = new User
        {
            Id = Guid.NewGuid(),
            ExternalId = externalId,
            Email = principal.FindFirstValue("email")
                    ?? principal.FindFirstValue("preferred_username"),
            DisplayName = principal.FindFirstValue("name"),
            CreatedAt = DateTimeOffset.UtcNow
        };
        db.Users.Add(user);
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            // Concurrent first request for the same identity — return whoever won.
            db.Entry(user).State = EntityState.Detached;
            user = await db.Users.FirstAsync(u => u.ExternalId == externalId, ct);
        }
        return user.Id;
    }
}
