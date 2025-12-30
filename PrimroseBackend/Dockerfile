FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
USER $APP_UID
WORKDIR /app
EXPOSE 8080
EXPOSE 8081

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY ["PrimroseBackend/PrimroseBackend.csproj", "PrimroseBackend/"]
RUN dotnet restore "PrimroseBackend/PrimroseBackend.csproj"
COPY . .
WORKDIR "/src/PrimroseBackend"
RUN dotnet build "./PrimroseBackend.csproj" -c $BUILD_CONFIGURATION -o /app/build

FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "./PrimroseBackend.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
# switch to root so we can write files and set permissions
USER root
COPY --from=publish /app/publish .
# copy the wait-for-db script into the final image and make it executable
COPY PrimroseBackend/wait-for-db.sh /app/wait-for-db.sh
RUN chmod +x /app/wait-for-db.sh
# restore non-root user
ARG APP_UID
USER $APP_UID
ENTRYPOINT ["/app/wait-for-db.sh"]
