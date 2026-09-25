# syntax=docker/dockerfile:1.7

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY src/TidalSonics.Server/TIDALSonics.Server.csproj src/TidalSonics.Server/
RUN dotnet restore src/TidalSonics.Server/TIDALSonics.Server.csproj

COPY src/TidalSonics.Server/ src/TidalSonics.Server/
RUN dotnet publish src/TidalSonics.Server/TIDALSonics.Server.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
EXPOSE 8080

COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "TIDALSonics.Server.dll"]
