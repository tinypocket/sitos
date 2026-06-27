using Microsoft.EntityFrameworkCore;
using Sitos.Api.Auth;
using Sitos.Api.Contracts;
using Sitos.Core.Entities;
using Sitos.Infrastructure;

namespace Sitos.Api.Endpoints;

public static class ProfileEndpoints
{
    public static IEndpointRouteBuilder MapProfileEndpoints(this IEndpointRouteBuilder app, bool requireAuth = false)
    {
        // GET /api/me — provisions and returns the caller.
        var me = app.MapGet("/api/me", async (SitosDbContext db, ICurrentUser user, CancellationToken ct) =>
        {
            var userId = await user.GetUserIdAsync(ct);
            var u = await db.Users.FirstAsync(x => x.Id == userId, ct);
            return Results.Ok(new { u.Id, u.Email, u.DisplayName });
        })
        .WithTags("Profile")
        .WithName("GetMe");
        if (requireAuth) me.RequireAuthorization();

        var group = app.MapGroup("/api/profile/goal").WithTags("Profile");
        if (requireAuth) group.RequireAuthorization();

        group.MapGet("", async (SitosDbContext db, ICurrentUser user, CancellationToken ct) =>
        {
            var userId = await user.GetUserIdAsync(ct);
            var goal = await db.Goals.FirstOrDefaultAsync(g => g.UserId == userId, ct);
            return goal is null ? Results.NoContent() : Results.Ok(GoalDto.From(goal));
        })
        .WithName("GetGoal")
        .WithSummary("Get the caller's calorie goal.");

        group.MapPut("", async (
            GoalDto req, SitosDbContext db, ICurrentUser user, CancellationToken ct) =>
        {
            if (req.DailyCalorieTarget <= 0) return Results.BadRequest("DailyCalorieTarget must be positive.");

            var userId = await user.GetUserIdAsync(ct);
            var goal = await db.Goals.FirstOrDefaultAsync(g => g.UserId == userId, ct);
            if (goal is null)
            {
                goal = new Goal { UserId = userId };
                db.Goals.Add(goal);
            }
            goal.DailyCalorieTarget = req.DailyCalorieTarget;
            goal.ProteinTargetGrams = req.ProteinTargetGrams;
            goal.CarbsTargetGrams = req.CarbsTargetGrams;
            goal.FatTargetGrams = req.FatTargetGrams;
            goal.UpdatedAt = DateTimeOffset.UtcNow;

            await db.SaveChangesAsync(ct);
            return Results.Ok(GoalDto.From(goal));
        })
        .WithName("SetGoal")
        .WithSummary("Set the caller's calorie goal.");

        return app;
    }
}
