namespace Sitos.Core.Entities;

/// <summary>
/// Local mirror of an authenticated identity. Keyed by the Entra External ID subject claim
/// (<see cref="ExternalId"/>); all user-owned data (diary, goals, custom foods) references
/// <see cref="Id"/>. This keeps the database the source of truth for analytics, independent
/// of the identity provider.
/// </summary>
public class User
{
    public Guid Id { get; set; }

    /// <summary>The Entra External ID subject/object id (the token's <c>sub</c>/<c>oid</c>).</summary>
    public string ExternalId { get; set; } = string.Empty;

    public string? Email { get; set; }
    public string? DisplayName { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
}
