namespace Sitos.Core;

/// <summary>Where a <see cref="Entities.Food"/> record originated.</summary>
public enum FoodSource
{
    OpenFoodFacts = 0,
    Usda = 1,
    UserContributed = 2,
    /// <summary>The per-serving "backing food" of a recipe. Excluded from search/recent lists.</summary>
    Recipe = 3
}

/// <summary>Trust level of a food record. Drives future cross-validation/sharing.</summary>
public enum VerifiedStatus
{
    Unverified = 0,
    CommunityValidated = 1,
    OfficialSource = 2
}

/// <summary>Unit a diary quantity is expressed in.</summary>
public enum QuantityUnit
{
    Servings = 0,
    Grams = 1
}

/// <summary>Which meal a diary entry belongs to.</summary>
public enum Meal
{
    Breakfast = 0,
    Lunch = 1,
    Dinner = 2,
    Snacks = 3
}
