namespace Sitos.Core.Entities;

/// <summary>A user's nutrition targets. One row per user (PK = <see cref="UserId"/>).</summary>
public class Goal
{
    public Guid UserId { get; set; }

    public int DailyCalorieTarget { get; set; }

    // Optional macro targets in grams (added to the model now, surfaced in the UI later).
    public int? ProteinTargetGrams { get; set; }
    public int? CarbsTargetGrams { get; set; }
    public int? FatTargetGrams { get; set; }

    public DateTimeOffset UpdatedAt { get; set; }
}
