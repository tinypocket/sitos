# Multi-stage build for the Sitos API. Build context = the server/ directory.
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY . .
RUN dotnet restore Sitos.slnx
RUN dotnet publish Sitos.Api/Sitos.Api.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app .
# Container Apps routes to this port; HTTPS/TLS is terminated at the ingress.
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080
ENTRYPOINT ["dotnet", "Sitos.Api.dll"]
