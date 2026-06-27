using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Sitos.Core.Abstractions;
using Sitos.Infrastructure.Providers;
using Sitos.Infrastructure.Services;

namespace Sitos.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddSitosInfrastructure(
        this IServiceCollection services, IConfiguration config)
    {
        services.AddDbContext<SitosDbContext>(opt =>
            opt.UseNpgsql(config.GetConnectionString("Postgres")));

        services.Configure<OpenFoodFactsOptions>(config.GetSection(OpenFoodFactsOptions.Section));
        services.Configure<UsdaOptions>(config.GetSection(UsdaOptions.Section));

        // Each provider gets its own typed HttpClient with a sensible timeout.
        services.AddHttpClient<IFoodProvider, OpenFoodFactsProvider>((sp, client) =>
        {
            var ua = config[$"{OpenFoodFactsOptions.Section}:UserAgent"]
                     ?? "Sitos/0.1 (https://github.com/tinypocket/sitos)";
            client.DefaultRequestHeaders.UserAgent.ParseAdd(ua);
            client.Timeout = TimeSpan.FromSeconds(10);
        });
        services.AddHttpClient<IFoodProvider, UsdaProvider>(client =>
            client.Timeout = TimeSpan.FromSeconds(10));

        services.AddScoped<IFoodService, FoodService>();

        return services;
    }
}
