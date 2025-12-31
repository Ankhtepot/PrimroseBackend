using System.Text;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Primitives;
using Microsoft.IdentityModel.Tokens;
using PrimroseBackend.Controllers;
using PrimroseBackend.Data;

WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

// Load secrets from Docker secrets files if env vars are missing
string? jwtSecret = builder.Configuration["JwtSecret"];
if (string.IsNullOrWhiteSpace(jwtSecret))
{
    const string jwtSecretPath = "/run/secrets/primrose_jwt";
    if (File.Exists(jwtSecretPath))
    {
        jwtSecret = File.ReadAllText(jwtSecretPath).Trim();
        if (!string.IsNullOrWhiteSpace(jwtSecret))
            Environment.SetEnvironmentVariable("JwtSecret", jwtSecret);
    }
}

string? sharedSecret = builder.Configuration["SharedSecret"];
if (string.IsNullOrWhiteSpace(sharedSecret))
{
    const string sharedSecretPath = "/run/secrets/primrose_shared";
    if (File.Exists(sharedSecretPath))
    {
        sharedSecret = File.ReadAllText(sharedSecretPath).Trim();
        if (!string.IsNullOrWhiteSpace(sharedSecret))
            Environment.SetEnvironmentVariable("SharedSecret", sharedSecret);
    }
}

// === Build SQL connection string (handle PasswordFile Docker secret) ===
string? configuredConn = builder.Configuration.GetConnectionString("DefaultConnection");
string finalConnection;
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
            string connNoPwdFile = Regex.Replace(configuredConn, "(?i)PasswordFile=[^;]+;?", "", RegexOptions.None);
            finalConnection = connNoPwdFile.TrimEnd(';') + ";Password=" + pwd + ";";
        }
        else
        {
            // fallback: try to read /run/secrets/db_password
            const string fallback = "/run/secrets/db_password";
            if (File.Exists(fallback))
            {
                string pwd = File.ReadAllText(fallback).Trim();
                string connNoPwdFile = Regex.Replace(configuredConn, "(?i)PasswordFile=[^;]+;?", "", RegexOptions.None);
                finalConnection = connNoPwdFile.TrimEnd(';') + ";Password=" + pwd + ";";
            }
            else
            {
                // leave configuredConn as-is (may fail later)
                finalConnection = configuredConn;
            }
        }
    }
    else
    {
        // no PasswordFile key: use configured connection string
        finalConnection = configuredConn;
    }
}
else
{
    // build default connection string using /run/secrets/db_password if present
    string pwd = string.Empty;
    const string fallback = "/run/secrets/db_password";
    if (File.Exists(fallback)) pwd = File.ReadAllText(fallback).Trim();
    finalConnection = $"Server=db;Database=GeneralDb;User=sa;Password={pwd};TrustServerCertificate=true;";
}

// === SERVICES ===
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(finalConnection));

builder.Services.AddMediatR(cfg => cfg.RegisterServicesFromAssembly(typeof(Program).Assembly));
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// CORS: read allowed origins from config (env var ALLOWED_ORIGINS as comma-separated list)
builder.Services.AddCors(options =>
{
    options.AddPolicy("React", policy =>
    {
        string allowed = builder.Configuration["AllowedOrigins"] ?? builder.Configuration["ALLOWED_ORIGINS"] ?? string.Empty;
        if (string.IsNullOrWhiteSpace(allowed))
        {
            // no origins configured: be restrictive by default (do not allow any origin)
            policy.AllowAnyHeader().AllowAnyMethod();
        }
        else
        {
            string[] origins = allowed.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            policy.WithOrigins(origins)
                  .AllowAnyHeader()
                  .AllowAnyMethod()
                  .AllowCredentials();
        }
    });

    options.AddPolicy("Public", p => p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod());
});

// JWT Auth
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        // prefer jwtSecret read from secrets file, fall back to configuration
        string? jwtSecretLocal = jwtSecret ?? builder.Configuration["JwtSecret"];
        if (string.IsNullOrWhiteSpace(jwtSecretLocal))
        {
            throw new InvalidOperationException("JwtSecret is missing");
        }

        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecretLocal)),
            ValidateIssuer = false,
            ValidateAudience = false,
            ClockSkew = TimeSpan.Zero
        };
    });

builder.Services.AddAuthorization();

WebApplication app = builder.Build();

// === SWAGGER ===
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseAuthentication();
app.UseAuthorization();

// Use the React CORS policy as the default for API endpoints (unless overridden per-endpoint)
app.UseCors("React");

// Health token: read from env or docker secret
string? healthToken = builder.Configuration["HEALTH_TOKEN"];
if (string.IsNullOrWhiteSpace(healthToken))
{
    const string healthTokenPath = "/run/secrets/primrose_health_token";
    if (File.Exists(healthTokenPath))
    {
        healthToken = File.ReadAllText(healthTokenPath).Trim();
    }
}

// lightweight health endpoint for readiness and monitoring (allow any origin or require token if set)
app.MapGet("/health", (HttpContext ctx) =>
{
    if (!string.IsNullOrWhiteSpace(healthToken))
    {
        // require X-Health-Token header to match
        if (!ctx.Request.Headers.TryGetValue("X-Health-Token", out StringValues val) || val != healthToken)
            return Results.StatusCode(StatusCodes.Status403Forbidden);
    }
    return Results.Ok(new { status = "ok" });
}).RequireCors("Public").WithName("Health");

app.MapPageEndpoints();

// Apply pending EF migrations and seed admin user from Docker secrets (idempotent)
using (IServiceScope scope = app.Services.CreateScope())
{
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

        // Read admin credentials from Docker secrets only
        const string adminUserPath = "/run/secrets/primrose_admin_username";
        const string adminPassPath = "/run/secrets/primrose_admin_password";

        string? adminUser = null;
        string? adminPass = null;

        if (File.Exists(adminUserPath) && File.Exists(adminPassPath))
        {
            adminUser = File.ReadAllText(adminUserPath).Trim();
            adminPass = File.ReadAllText(adminPassPath).Trim();
        }

        if (!string.IsNullOrWhiteSpace(adminUser) && !string.IsNullOrWhiteSpace(adminPass))
        {
            // seed only if admin does not exist
            if (!db.Admins.Any(a => a.Username == adminUser))
            {
                logger.LogInformation("Seeding admin user from Docker secrets: {User}", adminUser);
                string? hash = BCrypt.Net.BCrypt.HashPassword(adminPass);
                db.Admins.Add(new PrimroseBackend.Data.Models.Admin
                {
                    Username = adminUser,
                    PasswordHash = hash,
                    IsAdmin = true
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
            logger.LogWarning("Admin Docker secrets not found; no admin user was seeded. Expect primrose_admin_username and primrose_admin_password in /run/secrets");
        }
    }
    catch (Exception ex)
    {
        ILogger logger = app.Logger;
        logger.LogError(ex, "Unexpected error during migration/seed");
    }
}

app.Run();

