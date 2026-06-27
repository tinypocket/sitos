namespace Sitos.Infrastructure.Providers;

public class OpenFoodFactsOptions
{
    public const string Section = "OpenFoodFacts";
    public string BaseUrl { get; set; } = "https://world.openfoodfacts.org";
    /// <summary>The fast full-text search service (search-a-licious), separate from the product API.</summary>
    public string SearchUrl { get; set; } = "https://search.openfoodfacts.org";
    /// <summary>OFF asks API clients to identify themselves via User-Agent.</summary>
    public string UserAgent { get; set; } = "Sitos/0.1 (https://github.com/tinypocket/sitos)";
}

public class UsdaOptions
{
    public const string Section = "Usda";
    public string BaseUrl { get; set; } = "https://api.nal.usda.gov/fdc/v1";
    /// <summary>Free key from https://fdc.nal.usda.gov/api-key-signup.html. Optional fallback.</summary>
    public string? ApiKey { get; set; }
}
