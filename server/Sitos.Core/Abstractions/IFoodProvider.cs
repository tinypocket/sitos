using Sitos.Core.Entities;

namespace Sitos.Core.Abstractions;

/// <summary>
/// An external nutrition data source (Open Food Facts, USDA, ...). Implementations translate
/// the provider's response into an unsaved <see cref="Food"/>; persistence and caching are the
/// responsibility of <see cref="IFoodService"/>.
/// </summary>
public interface IFoodProvider
{
    /// <summary>Which source this provider represents. Also defines fallback priority order.</summary>
    FoodSource Source { get; }

    /// <summary>Look up a single product by barcode, or null if this provider has no match.</summary>
    Task<Food?> FindByBarcodeAsync(string barcode, CancellationToken ct = default);

    /// <summary>Free-text search. Returns an empty list when unsupported or no matches.</summary>
    Task<IReadOnlyList<Food>> SearchAsync(string query, CancellationToken ct = default);
}
