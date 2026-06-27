using Microsoft.EntityFrameworkCore;
using Sitos.Infrastructure;

namespace Sitos.Api.Auth;

/// <summary>
/// Resolves the local <c>User.Id</c> for the caller. In M1 this is a fixed dev user; in M2 it
/// will read the Entra subject claim and provision the user on first call. Endpoints depend only
/// on this abstraction, so swapping in real auth requires no endpoint changes.
/// </summary>
public interface ICurrentUser
{
    Task<Guid> GetUserIdAsync(CancellationToken ct = default);
}

/// <summary>M1 stand-in: always returns a single seeded development user.</summary>
public class DevCurrentUser(SitosDbContext db) : ICurrentUser
{
    public static readonly Guid DevUserId = Guid.Parse("00000000-0000-0000-0000-0000000000d3");
    private const string DevExternalId = "dev-local-user";

    public async Task<Guid> GetUserIdAsync(CancellationToken ct = default)
    {
        var exists = await db.Users.AnyAsync(u => u.Id == DevUserId, ct);
        if (!exists)
        {
            db.Users.Add(new Core.Entities.User
            {
                Id = DevUserId,
                ExternalId = DevExternalId,
                Email = "dev@sitos.local",
                DisplayName = "Dev User",
                CreatedAt = DateTimeOffset.UtcNow
            });
            await db.SaveChangesAsync(ct);
        }
        return DevUserId;
    }
}
