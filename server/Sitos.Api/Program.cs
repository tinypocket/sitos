using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Sitos.Api.Auth;
using Sitos.Api.Endpoints;
using Sitos.Infrastructure;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSitosInfrastructure(builder.Configuration);

// Auth: validate Entra External ID tokens when configured; otherwise fall back to the dev user
// so local development works without a tenant. The endpoints depend only on ICurrentUser.
var entra = builder.Configuration.GetSection(EntraExternalIdOptions.Section).Get<EntraExternalIdOptions>()
            ?? new EntraExternalIdOptions();
var authEnabled = entra.IsConfigured;

if (authEnabled)
{
    builder.Services.AddHttpContextAccessor();
    builder.Services.AddScoped<ICurrentUser, EntraCurrentUser>();
    builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
        .AddJwtBearer(options =>
        {
            options.Authority = entra.Authority;
            options.Audience = entra.Audience;
            options.MapInboundClaims = false; // keep raw claim names (oid, sub, email)
            options.TokenValidationParameters.ValidateIssuer = true;
        });
    builder.Services.AddAuthorization();
}
else
{
    builder.Services.AddScoped<ICurrentUser, DevCurrentUser>();
}

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

if (authEnabled)
{
    app.UseAuthentication();
    app.UseAuthorization();
}

app.MapGet("/health", () => Results.Ok(new { status = "ok" })).WithTags("Health");

// Data endpoints require auth when Entra is configured; /health stays anonymous.
app.MapFoodEndpoints(authEnabled);
app.MapDiaryEndpoints(authEnabled);
app.MapProfileEndpoints(authEnabled);

app.Run();

// Exposed so the integration test project can reference the entry point via WebApplicationFactory.
public partial class Program;
