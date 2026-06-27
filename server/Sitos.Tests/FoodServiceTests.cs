using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Sitos.Core;
using Sitos.Core.Abstractions;
using Sitos.Core.Entities;
using Sitos.Infrastructure;
using Sitos.Infrastructure.Services;
using Xunit;

namespace Sitos.Tests;

public class FoodServiceTests
{
    private static SitosDbContext NewDb() =>
        new(new DbContextOptionsBuilder<SitosDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options);

    /// <summary>A provider that records how many times it was hit.</summary>
    private sealed class CountingProvider(FoodSource source, Food? result) : IFoodProvider
    {
        public int BarcodeCalls { get; private set; }
        public FoodSource Source => source;

        public Task<Food?> FindByBarcodeAsync(string barcode, CancellationToken ct = default)
        {
            BarcodeCalls++;
            return Task.FromResult(result);
        }

        public Task<IReadOnlyList<Food>> SearchAsync(string query, CancellationToken ct = default) =>
            Task.FromResult<IReadOnlyList<Food>>([]);
    }

    [Fact]
    public async Task GetByBarcode_caches_then_serves_from_cache()
    {
        await using var db = NewDb();
        var provider = new CountingProvider(FoodSource.OpenFoodFacts, new Food
        {
            Barcode = "111", Name = "Test Bar", CaloriesPer100g = 500
        });
        var svc = new FoodService(db, [provider], NullLogger<FoodService>.Instance);

        var first = await svc.GetByBarcodeAsync("111");
        var second = await svc.GetByBarcodeAsync("111");

        Assert.NotNull(first);
        Assert.Equal(first!.Id, second!.Id);
        Assert.Equal(1, provider.BarcodeCalls);           // provider hit only once
        Assert.Equal(1, await db.Foods.CountAsync());      // exactly one cached row
    }

    [Fact]
    public async Task GetByBarcode_tries_providers_in_priority_order()
    {
        await using var db = NewDb();
        var usda = new CountingProvider(FoodSource.Usda, new Food
        {
            Barcode = "222", Name = "From USDA", CaloriesPer100g = 100, Source = FoodSource.Usda
        });
        var off = new CountingProvider(FoodSource.OpenFoodFacts, null); // OFF misses

        // Pass USDA first to prove ordering is by source, not argument order.
        var svc = new FoodService(db, [usda, off], NullLogger<FoodService>.Instance);

        var result = await svc.GetByBarcodeAsync("222");

        Assert.NotNull(result);
        Assert.Equal(FoodSource.Usda, result!.Source);
        Assert.Equal(1, off.BarcodeCalls);  // OFF tried first (priority 0) and missed
        Assert.Equal(1, usda.BarcodeCalls); // then USDA hit
    }

    [Fact]
    public async Task GetByBarcode_returns_null_when_no_provider_matches()
    {
        await using var db = NewDb();
        var off = new CountingProvider(FoodSource.OpenFoodFacts, null);
        var svc = new FoodService(db, [off], NullLogger<FoodService>.Instance);

        Assert.Null(await svc.GetByBarcodeAsync("999"));
        Assert.Equal(0, await db.Foods.CountAsync());
    }

    [Fact]
    public async Task AddUserFood_marks_source_and_owner()
    {
        await using var db = NewDb();
        var svc = new FoodService(db, [], NullLogger<FoodService>.Instance);
        var userId = Guid.NewGuid();

        var saved = await svc.AddUserFoodAsync(
            new Food { Name = "My Smoothie", CaloriesPer100g = 60 }, userId);

        Assert.Equal(FoodSource.UserContributed, saved.Source);
        Assert.Equal(userId, saved.CreatedByUserId);
        Assert.NotEqual(Guid.Empty, saved.Id);
    }
}
