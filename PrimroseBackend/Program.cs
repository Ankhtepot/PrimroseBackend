using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
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

// === SERVICES ===
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")
                         ??
                         "Server=db;Database=GeneralDb;User=sa;PasswordFile=/run/secrets/db_password;TrustServerCertificate=true"));

builder.Services.AddMediatR(cfg => cfg.RegisterServicesFromAssembly(typeof(Program).Assembly));
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// CORS: read allowed origins from config (env var ALLOWED_ORIGINS as comma-separated list)
builder.Services.AddCors(options =>
{
    options.AddPolicy("React", policy =>
    {
        var allowed = builder.Configuration["AllowedOrigins"] ?? builder.Configuration["ALLOWED_ORIGINS"] ?? string.Empty;
        if (string.IsNullOrWhiteSpace(allowed))
        {
            // no origins configured: be restrictive by default (do not allow any origin)
            policy.AllowAnyHeader().AllowAnyMethod();
        }
        else
        {
            var origins = allowed.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
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
        if (!ctx.Request.Headers.TryGetValue("X-Health-Token", out var val) || val != healthToken)
            return Results.StatusCode(StatusCodes.Status403Forbidden);
    }
    return Results.Ok(new { status = "ok" });
}).RequireCors("Public").WithName("Health");

app.MapPageEndpoints();

app.Run();

