using Microsoft.EntityFrameworkCore;
using Sitos.Api.Auth;
using Sitos.Api.Endpoints;
using Sitos.Infrastructure;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSitosInfrastructure(builder.Configuration);

// M1: single dev user. Replaced by Entra-claim-based resolution in M2.
builder.Services.AddScoped<ICurrentUser, DevCurrentUser>();

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Locked-down CORS; the Flutter app origin(s) get added as we wire up the client.
builder.Services.AddCors(o => o.AddPolicy("app", p => p
    .AllowAnyHeader().AllowAnyMethod()
    .WithOrigins("http://localhost", "http://localhost:8080")));

var app = builder.Build();

// Apply migrations on startup for a frictionless local/dev experience.
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<SitosDbContext>();
    await db.Database.MigrateAsync();
}

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseCors("app");

app.MapGet("/health", () => Results.Ok(new { status = "ok" })).WithTags("Health");
app.MapFoodEndpoints();
app.MapDiaryEndpoints();
app.MapProfileEndpoints();

app.Run();

// Exposed so the integration test project can reference the entry point via WebApplicationFactory.
public partial class Program;
