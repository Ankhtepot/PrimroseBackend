FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
ARG APP_UID=1000
USER root
WORKDIR /app
EXPOSE 8080
EXPOSE 8081

# install gosu for dropping privileges at runtime
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates gnupg2 gosu \
  && rm -rf /var/lib/apt/lists/*

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
# keep root here so entrypoint can fix permissions
USER root
COPY --from=publish /app/publish .
# copy the wait-for-db script into the final image and make it executable
COPY PrimroseBackend/wait-for-db.sh /app/wait-for-db.sh
RUN chmod +x /app/wait-for-db.sh
# set APP_UID arg for runtime use (default 1000)
ARG APP_UID=1000
ENV APP_UID=${APP_UID}
# entrypoint runs as root and will use gosu to drop to APP_UID when exec'ing the app
ENTRYPOINT ["/app/wait-for-db.sh"]
