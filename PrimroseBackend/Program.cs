using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using PrimroseBackend.Data;
using Microsoft.AspNetCore.HttpOverrides; // added for forwarded headers
using PrimroseBackend.Controllers; // register minimal API endpoints (MapPageEndpoints)
using static PrimroseBackend.Configuration.EnvironmentInitialization;

WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

// Configure forwarded headers so app correctly detects original scheme/IP when behind proxy/load-balancer
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    // Clear defaults so Docker/Nginx reverse proxies aren't rejected when running in unknown network environments
    options.KnownIPNetworks.Clear();
    options.KnownProxies.Clear();
});

// Configure HTTPS redirection defaults (useful when TLS terminates at a reverse proxy)
builder.Services.AddHttpsRedirection(options =>
{
    options.HttpsPort = 443;
    options.RedirectStatusCode = StatusCodes.Status308PermanentRedirect;
});

string? jwtSecret = ResolveJwtSecret(builder);
ResolveHealthToken(builder);
LoadSharedSecretFromDocker(builder);

// === Build SQL connection string (handle PasswordFile Docker secret) ===
string finalConnection = ResolveDbConnection(builder);

// === SERVICES ===
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(finalConnection));

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

// Ensure forwarded headers middleware runs early so HTTPS redirection and auth see correct scheme
app.UseForwardedHeaders();

// === SWAGGER ===
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// Use the React CORS policy as the default for API endpoints (unless overridden per-endpoint)
app.UseCors("React");

// Make HTTPS redirection conditional so local direct HTTP requests (curl tests) don't get 308
// Set ENABLE_HTTPS_REDIRECT=true in production / reverse-proxy environments where TLS is required
var enableHttpsRedirect = builder.Configuration["ENABLE_HTTPS_REDIRECT"];
if (string.Equals(enableHttpsRedirect, "true", StringComparison.OrdinalIgnoreCase) || app.Environment.IsDevelopment())
{
    app.UseHttpsRedirection();
}
else
{
    app.Logger.LogInformation("HTTPS redirection is disabled. To enable, set ENABLE_HTTPS_REDIRECT=true in configuration or environment.");
}

app.UseAuthentication();
app.UseAuthorization();

app.MapAdminEndpoints();
app.MapPageEndpoints();

SeedAdminUser(app);

app.Run();

