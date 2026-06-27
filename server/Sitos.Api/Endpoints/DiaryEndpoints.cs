using Microsoft.EntityFrameworkCore;
using Sitos.Api.Auth;
using Sitos.Api.Contracts;
using Sitos.Core.Entities;
using Sitos.Infrastructure;

namespace Sitos.Api.Endpoints;

public static class DiaryEndpoints
{
    public static IEndpointRouteBuilder MapDiaryEndpoints(this IEndpointRouteBuilder app, bool requireAuth = false)
    {
        var group = app.MapGroup("/api/diary").WithTags("Diary");
        if (requireAuth) group.RequireAuthorization();

        // A day's log with rolled-up totals and the user's calorie goal.
        group.MapGet("", async (
            DateOnly? date, SitosDbContext db, ICurrentUser user, CancellationToken ct) =>
        {
            var userId = await user.GetUserIdAsync(ct);
            var day = date ?? DateOnly.FromDateTime(DateTime.UtcNow);

            var entries = await db.DiaryEntries
                .Include(e => e.Food)
                .Where(e => e.UserId == userId && e.Date == day)
                .OrderBy(e => e.CreatedAt)
                .ToListAsync(ct);

            var dtos = entries.Select(DiaryEntryDto.From).ToList();
            var goal = await db.Goals.FirstOrDefaultAsync(g => g.UserId == userId, ct);

            return Results.Ok(new DiaryDayDto(
                day,
                Math.Round(dtos.Sum(e => e.Calories), 1),
                Math.Round(dtos.Sum(e => e.Protein), 1),
                Math.Round(dtos.Sum(e => e.Carbs), 1),
                Math.Round(dtos.Sum(e => e.Fat), 1),
                goal?.DailyCalorieTarget,
                dtos));
        })
        .WithName("GetDiaryDay")
        .WithSummary("Get a day's diary entries with totals.");

        // Log a food.
        group.MapPost("", async (
            CreateDiaryEntryRequest req, SitosDbContext db, ICurrentUser user, CancellationToken ct) =>
        {
            if (req.Quantity <= 0) return Results.BadRequest("Quantity must be positive.");
            var foodExists = await db.Foods.AnyAsync(f => f.Id == req.FoodId, ct);
            if (!foodExists) return Results.BadRequest("Unknown foodId.");

            var userId = await user.GetUserIdAsync(ct);
            var entry = new DiaryEntry
            {
                Id = Guid.NewGuid(),
                UserId = userId,
                FoodId = req.FoodId,
                Date = req.Date,
                Quantity = req.Quantity,
                Unit = req.Unit,
                CreatedAt = DateTimeOffset.UtcNow
            };
            db.DiaryEntries.Add(entry);
            await db.SaveChangesAsync(ct);

            // Reload with food for the response projection.
            await db.Entry(entry).Reference(e => e.Food).LoadAsync(ct);
            return Results.Created($"/api/diary/{entry.Id}", DiaryEntryDto.From(entry));
        })
        .WithName("CreateDiaryEntry")
        .WithSummary("Log a food to the diary.");

        // Update quantity/unit of an entry the caller owns.
        group.MapPut("/{id:guid}", async (
            Guid id, CreateDiaryEntryRequest req, SitosDbContext db, ICurrentUser user, CancellationToken ct) =>
        {
            var userId = await user.GetUserIdAsync(ct);
            var entry = await db.DiaryEntries.Include(e => e.Food)
                .FirstOrDefaultAsync(e => e.Id == id && e.UserId == userId, ct);
            if (entry is null) return Results.NotFound();
            if (req.Quantity <= 0) return Results.BadRequest("Quantity must be positive.");

            entry.Quantity = req.Quantity;
            entry.Unit = req.Unit;
            entry.Date = req.Date;
            await db.SaveChangesAsync(ct);
            return Results.Ok(DiaryEntryDto.From(entry));
        })
        .WithName("UpdateDiaryEntry");

        // Delete an entry the caller owns.
        group.MapDelete("/{id:guid}", async (
            Guid id, SitosDbContext db, ICurrentUser user, CancellationToken ct) =>
        {
            var userId = await user.GetUserIdAsync(ct);
            var entry = await db.DiaryEntries
                .FirstOrDefaultAsync(e => e.Id == id && e.UserId == userId, ct);
            if (entry is null) return Results.NotFound();

            db.DiaryEntries.Remove(entry);
            await db.SaveChangesAsync(ct);
            return Results.NoContent();
        })
        .WithName("DeleteDiaryEntry");

        return app;
    }
}
