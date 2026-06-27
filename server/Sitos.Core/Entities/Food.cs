namespace Sitos.Core.Entities;

/// <summary>
/// A food item. Nutrition is normalised to a per-100g basis (the convention used by
/// Open Food Facts and USDA), so any serving size can be derived. This table doubles as
/// the shared, growing cache: every product fetched from an external provider is persisted
/// here, and user-contributed foods live here too (distinguished by <see cref="Source"/>).
/// </summary>
public class Food
{
    public Guid Id { get; set; }

    /// <summary>UPC/EAN barcode. Null for custom foods without one. Unique when present.</summary>
    public string? Barcode { get; set; }

    public string Name { get; set; } = string.Empty;
    public string? Brand { get; set; }

    /// <summary>Grams in one serving, when known (lets us show "per serving" values).</summary>
    public double? ServingSizeGrams { get; set; }

    /// <summary>Human-readable serving, e.g. "1 cup (240 ml)".</summary>
    public string? ServingSizeLabel { get; set; }

    // ----- Nutrition, per 100 g -----
    public double CaloriesPer100g { get; set; }
    public double ProteinPer100g { get; set; }
    public double CarbsPer100g { get; set; }
    public double FatPer100g { get; set; }

    public FoodSource Source { get; set; }

    /// <summary>The provider's own identifier (OFF code, USDA fdcId).</summary>
    public string? SourceId { get; set; }

    /// <summary>Raw provider payload (stored as jsonb) for future re-parsing/validation.</summary>
    public string? RawJson { get; set; }

    public VerifiedStatus VerifiedStatus { get; set; } = VerifiedStatus.Unverified;

    /// <summary>Set for user-contributed foods.</summary>
    public Guid? CreatedByUserId { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
}
