using Microsoft.EntityFrameworkCore;
using Sitos.Core.Entities;

namespace Sitos.Infrastructure;

public class SitosDbContext(DbContextOptions<SitosDbContext> options) : DbContext(options)
{
    public DbSet<Food> Foods => Set<Food>();
    public DbSet<User> Users => Set<User>();
    public DbSet<DiaryEntry> DiaryEntries => Set<DiaryEntry>();
    public DbSet<Goal> Goals => Set<Goal>();
    public DbSet<Recipe> Recipes => Set<Recipe>();
    public DbSet<RecipeIngredient> RecipeIngredients => Set<RecipeIngredient>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<Food>(e =>
        {
            e.HasKey(x => x.Id);
            e.Property(x => x.Name).IsRequired().HasMaxLength(512);
            e.Property(x => x.Brand).HasMaxLength(256);
            e.Property(x => x.Barcode).HasMaxLength(64);
            e.Property(x => x.SourceId).HasMaxLength(128);
            e.Property(x => x.RawJson).HasColumnType("jsonb");
            // Unique barcode when present; multiple custom foods may have NULL barcode.
            e.HasIndex(x => x.Barcode).IsUnique().HasFilter("\"Barcode\" IS NOT NULL");
            e.HasIndex(x => x.Name);
        });

        b.Entity<User>(e =>
        {
            e.HasKey(x => x.Id);
            e.Property(x => x.ExternalId).IsRequired().HasMaxLength(128);
            e.Property(x => x.Email).HasMaxLength(320);
            e.Property(x => x.DisplayName).HasMaxLength(256);
            e.HasIndex(x => x.ExternalId).IsUnique();
        });

        b.Entity<DiaryEntry>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasOne(x => x.Food).WithMany().HasForeignKey(x => x.FoodId).OnDelete(DeleteBehavior.Restrict);
            e.HasIndex(x => new { x.UserId, x.Date });
        });

        b.Entity<Goal>(e =>
        {
            e.HasKey(x => x.UserId); // one goal row per user
        });

        b.Entity<Recipe>(e =>
        {
            e.HasKey(x => x.Id);
            e.Property(x => x.Name).IsRequired().HasMaxLength(256);
            e.HasIndex(x => x.UserId);
            e.HasOne(x => x.BackingFood).WithMany().HasForeignKey(x => x.BackingFoodId)
                .OnDelete(DeleteBehavior.Restrict);
            e.HasMany(x => x.Ingredients).WithOne().HasForeignKey(x => x.RecipeId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<RecipeIngredient>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasOne(x => x.Food).WithMany().HasForeignKey(x => x.FoodId)
                .OnDelete(DeleteBehavior.Restrict);
        });
    }
}
