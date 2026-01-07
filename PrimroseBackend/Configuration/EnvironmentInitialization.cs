using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using PrimroseBackend.Data;
using PrimroseBackend.Data.Models;

namespace PrimroseBackend.Configuration;

public static class EnvironmentInitialization
{
    public static string? ResolveJwtSecret(WebApplicationBuilder webApplicationBuilder)
    {
        // Load secrets from Docker secrets files if env vars are missing
        string? s = webApplicationBuilder.Configuration["JwtSecret"];
        if (string.IsNullOrWhiteSpace(s))
        {
            string[] paths = ["/run/secrets/primrose_jwt", "/run/secrets/jwt_secret"];
            foreach (var path in paths)
            {
                if (File.Exists(path))
                {
                    s = File.ReadAllText(path).Trim();
                    if (!string.IsNullOrWhiteSpace(s))
                    {
                        Environment.SetEnvironmentVariable("JwtSecret", s);
                        break;
                    }
                }
            }
        }

        return s;
    }

    public static string? ResolveHealthToken(WebApplicationBuilder webApplicationBuilder)
    {
        string? healthToken = webApplicationBuilder.Configuration["PRIMROSE_HEALTH_TOKEN"] ?? webApplicationBuilder.Configuration["HEALTH_TOKEN"];
        if (string.IsNullOrWhiteSpace(healthToken))
        {
            string[] paths = ["/run/secrets/primrose_health_token", "/run/secrets/health_token"];
            foreach (var path in paths)
            {
                if (File.Exists(path))
                {
                    healthToken = File.ReadAllText(path).Trim();
                    if (!string.IsNullOrWhiteSpace(healthToken))
                    {
                        Environment.SetEnvironmentVariable("PRIMROSE_HEALTH_TOKEN", healthToken);
                        break;
                    }
                }
            }
        }

        return healthToken;
    }

    public static void LoadSharedSecretFromDocker(WebApplicationBuilder webApplicationBuilder)
    {
        string? sharedSecret = webApplicationBuilder.Configuration["SharedSecret"];
        if (string.IsNullOrWhiteSpace(sharedSecret))
        {
            string[] paths = ["/run/secrets/primrose_shared", "/run/secrets/shared_secret"];
            foreach (var path in paths)
            {
                if (File.Exists(path))
                {
                    sharedSecret = File.ReadAllText(path).Trim();
                    if (!string.IsNullOrWhiteSpace(sharedSecret))
                    {
                        Environment.SetEnvironmentVariable("SharedSecret", sharedSecret);
                        break;
                    }
                }
            }
        }
    }

    public static void SeedAdminUser(WebApplication app)
    {
        // Apply pending EF migrations and seed admin user from Docker secrets (idempotent)
        using IServiceScope scope = app.Services.CreateScope();
        
        try
        {
            ILogger<Program> logger = scope.ServiceProvider.GetRequiredService<ILogger<Program>>();
            AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

            logger.LogInformation("Applying database migrations (if any)");
            try
            {
                db.Database.Migrate();
                logger.LogInformation("Database migrations applied");
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Database migration failed or skipped");
            }

            // Read admin credentials from Docker secrets
            string[] userPaths = ["/run/secrets/primrose_admin_username", "/run/secrets/admin_username"];
            string[] passPaths = ["/run/secrets/primrose_admin_password", "/run/secrets/admin_password"];

            string? adminUser = null;
            string? adminPass = null;

            foreach (var path in userPaths)
            {
                if (File.Exists(path))
                {
                    adminUser = File.ReadAllText(path).Trim();
                    break;
                }
            }

            foreach (var path in passPaths)
            {
                if (File.Exists(path))
                {
                    adminPass = File.ReadAllText(path).Trim();
                    break;
                }
            }

            if (!string.IsNullOrWhiteSpace(adminUser) && !string.IsNullOrWhiteSpace(adminPass))
            {
                // seed only if admin does not exist
                if (!db.Admins.Any(a => a.Username == adminUser))
                {
                    logger.LogInformation("Seeding admin user from Docker secrets: {User}", adminUser);
                    string? hash = BCrypt.Net.BCrypt.HashPassword(adminPass);
                    db.Admins.Add(new Admin
                    {
                        Username = adminUser,
                        PasswordHash = hash,
                        IsAdmin = true,
                        Role = "Admin",
                        CreatedAt = DateTime.UtcNow
                    });
                    db.SaveChanges();
                    logger.LogInformation("Admin user seeded");
                }
                else
                {
                    logger.LogInformation("Admin user {User} already exists, skipping seed", adminUser);
                }
            }
            else
            {
                logger.LogWarning(
                    "Admin Docker secrets not found; no admin user was seeded. Expect primrose_admin_username and primrose_admin_password in /run/secrets");
            }
        }
        catch (Exception ex)
        {
            ILogger logger = app.Logger;
            logger.LogError(ex, "Unexpected error during migration/seed");
        }
    }

    public static string ResolveDbConnection(WebApplicationBuilder webApplicationBuilder)
    {
        string finalString;
        string? configuredConn = webApplicationBuilder.Configuration.GetConnectionString("DefaultConnection");
        if (!string.IsNullOrWhiteSpace(configuredConn))
        {
            // If the connection string contains PasswordFile=..., replace it with actual Password from file
            Match m = Regex.Match(configuredConn, "(?i)PasswordFile=([^;]+)");
            if (m.Success)
            {
                string path = m.Groups[1].Value;
                // trim surrounding quotes if present
                path = path.Trim('"', '\'');
                // if path is NOT absolute, allow relative to repo root or /run/secrets
                if (!Path.IsPathRooted(path) && File.Exists(Path.Combine("/run/secrets", path)))
                    path = Path.Combine("/run/secrets", path);

                if (File.Exists(path))
                {
                    string pwd = File.ReadAllText(path).Trim();
                    // remove PasswordFile=... segment and append Password=...
                    string connNoPwdFile =
                        Regex.Replace(configuredConn, "(?i)PasswordFile=[^;]+;?", "", RegexOptions.None);
                    finalString = connNoPwdFile.TrimEnd(';') + ";Password=" + pwd + ";";
                }
                else
                {
                    // fallback: try to read /run/secrets/db_password
                    const string fallback = "/run/secrets/db_password";
                    if (File.Exists(fallback))
                    {
                        string pwd = File.ReadAllText(fallback).Trim();
                        string connNoPwdFile = Regex.Replace(configuredConn, "(?i)PasswordFile=[^;]+;?", "",
                            RegexOptions.None);
                        finalString = connNoPwdFile.TrimEnd(';') + ";Password=" + pwd + ";";
                    }
                    else
                    {
                        // leave configuredConn as-is (may fail later)
                        finalString = configuredConn;
                    }
                }
            }
            else
            {
                // no PasswordFile key: use configured connection string
                finalString = configuredConn;
            }
        }
        else
        {
            // build default connection string using /run/secrets/db_password if present
            string pwd = string.Empty;
            const string fallback = "/run/secrets/db_password";
            if (File.Exists(fallback)) pwd = File.ReadAllText(fallback).Trim();
            finalString = $"Server=db;Database=GeneralDb;User=sa;Password={pwd};TrustServerCertificate=true;";
        }

        return finalString;
    }
}