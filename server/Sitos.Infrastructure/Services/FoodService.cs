using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Sitos.Core.Abstractions;
using Sitos.Core.Entities;

namespace Sitos.Infrastructure.Services;

/// <summary>
/// Cache-first food resolution. The local <see cref="SitosDbContext.Foods"/> table is the cache:
/// on a barcode miss we query providers in priority order, persist the first hit, and return it,
/// so the shared food database grows with use.
/// </summary>
public class FoodService(
    SitosDbContext db,
    IEnumerable<IFoodProvider> providers,
    ILogger<FoodService> logger) : IFoodService
{
    // Order providers by their source enum so Open Food Facts (0) is tried before USDA (1).
    private readonly IReadOnlyList<IFoodProvider> _providers =
        providers.OrderBy(p => (int)p.Source).ToList();

    public async Task<Food?> GetByBarcodeAsync(string barcode, CancellationToken ct = default)
    {
        barcode = barcode.Trim();

        var cached = await db.Foods.FirstOrDefaultAsync(f => f.Barcode == barcode, ct);
        if (cached is not null)
        {
            logger.LogDebug("Cache hit for barcode {Barcode}", barcode);
            return cached;
        }

        foreach (var provider in _providers)
        {
            var found = await provider.FindByBarcodeAsync(barcode, ct);
            if (found is null) continue;

            logger.LogInformation("Caching {Barcode} from {Source}", barcode, provider.Source);
            return await PersistAsync(found, ct);
        }

        return null;
    }

    public async Task<IReadOnlyList<Food>> SearchAsync(string query, CancellationToken ct = default)
    {
        query = query.Trim();

        // Local cache results first (instant, already-known foods). Recipe backing foods are
        // managed via the recipes feature, so they're kept out of plain food search.
        var local = await db.Foods
            .Where(f => f.Source != Core.FoodSource.Recipe && EF.Functions.ILike(f.Name, $"%{query}%"))
            .OrderBy(f => f.Name)
            .Take(20)
            .ToListAsync(ct);

        var byBarcode = local.Where(f => f.Barcode is not null).ToDictionary(f => f.Barcode!);
        var results = new List<Food>(local);

        // Then top up from the primary provider, de-duplicating by barcode.
        var primary = _providers.FirstOrDefault();
        if (primary is not null && results.Count < 20)
        {
            foreach (var hit in await primary.SearchAsync(query, ct))
            {
                if (hit.Barcode is not null && byBarcode.ContainsKey(hit.Barcode)) continue;
                results.Add(hit); // transient (not persisted until logged/selected)
                if (results.Count >= 20) break;
            }
        }

        return results;
    }

    public async Task<Food> AddUserFoodAsync(Food food, Guid userId, CancellationToken ct = default)
    {
        food.Source = Core.FoodSource.UserContributed;
        food.CreatedByUserId = userId;
        food.VerifiedStatus = Core.VerifiedStatus.Unverified;
        return await PersistAsync(food, ct);
    }

    private async Task<Food> PersistAsync(Food food, CancellationToken ct)
    {
        food.Id = food.Id == Guid.Empty ? Guid.NewGuid() : food.Id;
        var now = DateTimeOffset.UtcNow;
        food.CreatedAt = now;
        food.UpdatedAt = now;

        db.Foods.Add(food);
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException) when (food.Barcode is not null)
        {
            // Lost a race to cache the same barcode — return the row that won.
            db.Entry(food).State = EntityState.Detached;
            var existing = await db.Foods.FirstOrDefaultAsync(f => f.Barcode == food.Barcode, ct);
            if (existing is not null) return existing;
            throw;
        }
        return food;
    }
}
