using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Sitos.Api.Auth;
using Sitos.Api.Endpoints;
using Sitos.Infrastructure;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSitosInfrastructure(builder.Configuration);

// Auth: validate OIDC tokens (Google, Entra, ...) when configured; otherwise fall back to the
// dev user so local development works without an identity provider. Endpoints depend only on
// ICurrentUser, so the rest of the app is unaffected by which provider is used.
var auth = builder.Configuration.GetSection(AuthOptions.Section).Get<AuthOptions>() ?? new AuthOptions();
var authEnabled = auth.IsConfigured;

if (authEnabled)
{
    builder.Services.AddHttpContextAccessor();
    builder.Services.AddScoped<ICurrentUser, OidcCurrentUser>();
    builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
        .AddJwtBearer(options =>
        {
            options.Authority = auth.Authority;
            options.Audience = auth.Audience;
            options.MapInboundClaims = false; // keep raw claim names (sub, oid, email, name)
            options.TokenValidationParameters.ValidateIssuer = true;
            // Google has historically issued both forms of the issuer; accept either.
            if (auth.Authority!.Contains("accounts.google.com"))
            {
                options.TokenValidationParameters.ValidIssuers =
                    ["https://accounts.google.com", "accounts.google.com"];
            }
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
