using Sitos.Core.Entities;

namespace Sitos.Core.Abstractions;

/// <summary>
/// Orchestrates food lookups: cache-first against the local database, falling back to external
/// providers (and persisting their results so the cache grows over time).
/// </summary>
public interface IFoodService
{
    /// <summary>
    /// Resolve a barcode. Checks the local cache first; on a miss, queries providers in priority
    /// order, persists the first hit, and returns it. Null if nothing matches anywhere.
    /// </summary>
    Task<Food?> GetByBarcodeAsync(string barcode, CancellationToken ct = default);

    /// <summary>Search the local cache and external providers, de-duplicated by barcode.</summary>
    Task<IReadOnlyList<Food>> SearchAsync(string query, CancellationToken ct = default);

    /// <summary>Persist a user-contributed food.</summary>
    Task<Food> AddUserFoodAsync(Food food, Guid userId, CancellationToken ct = default);
}
