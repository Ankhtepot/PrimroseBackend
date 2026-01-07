using System.Collections.Concurrent;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Primitives;
using Microsoft.IdentityModel.Tokens;
using PrimroseBackend.Data;
using PrimroseBackend.Data.Dtos;
using PrimroseBackend.Data.Models;

namespace PrimroseBackend.Controllers;

public static class AdminEndpoints
{
    public static WebApplication MapAdminEndpoints(this WebApplication app)
    {
        app.MapPost("/api/auth/login", async (LoginDto request, AppDbContext db, IConfiguration config) =>
        {
            if (string.IsNullOrWhiteSpace(request.Username) || string.IsNullOrWhiteSpace(request.Password))
                return Results.Unauthorized();

            Admin? admin = await db.Admins.SingleOrDefaultAsync(a => a.Username == request.Username);
            if (admin == null)
                return Results.Unauthorized();

            bool passwordOk = false;
            try
            {
                passwordOk = BCrypt.Net.BCrypt.Verify(request.Password, admin.PasswordHash);
            }
            catch
            {
                passwordOk = false;
            }

            if (!passwordOk)
                return Results.Unauthorized();

            // get jwt secret from environment (set at startup) or config
            string? jwtSecret = Environment.GetEnvironmentVariable("JwtSecret") ?? config["JwtSecret"];
            if (string.IsNullOrWhiteSpace(jwtSecret))
                throw new InvalidOperationException("JwtSecret is missing");

            SymmetricSecurityKey key = new(Encoding.UTF8.GetBytes(jwtSecret));
            SigningCredentials credentials = new(key, SecurityAlgorithms.HmacSha256);

            // 1. Prepare claims list
            var claims = new List<Claim>
            {
                new Claim(ClaimTypes.Name, request.Username),
                new Claim("IsAdmin", admin.IsAdmin.ToString().ToLower())
            };

            // 2. Split roles from the string and add them as claims
            if (!string.IsNullOrWhiteSpace(admin.Role))
            {
                var roles = admin.Role.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                foreach (var role in roles)
                {
                    claims.Add(new Claim(ClaimTypes.Role, role));
                }
            }

            // 3. Create the token with the claims list
            JwtSecurityToken token = new(
                expires: DateTime.UtcNow.AddDays(1),
                signingCredentials: credentials,
                claims: claims
            );

            return Results.Ok(new {Token = new JwtSecurityTokenHandler().WriteToken(token)});
        });

        // Map a dedicated branch for /health before HTTPS redirection so probes don't get 308 redirects
        app.Map("/health", branch =>
        {
            // Allow public CORS for health checks
            branch.UseCors("Public");

            // Simple in-memory IP-based rate limiter (per-minute window)
            // Note: this is intentionally small and in-process; for multi-node clusters use a distributed store.
            ConcurrentDictionary<string, (int Count, DateTime WindowStart)> rateLimitStore = new();
            const int LIMIT = 10; // requests per window
            TimeSpan WINDOW = TimeSpan.FromMinutes(1);

            branch.Run(async ctx =>
            {
                // Health token: read from env (set at startup) or config
                IConfiguration config = ctx.RequestServices.GetRequiredService<IConfiguration>();
                string? healthToken = Environment.GetEnvironmentVariable("HEALTH_TOKEN") ?? config["HEALTH_TOKEN"];

                // If a health token is configured, require it via X-Health-Token header
                if (!string.IsNullOrWhiteSpace(healthToken))
                {
                    if (!ctx.Request.Headers.TryGetValue("X-Health-Token", out StringValues val) || val != healthToken)
                    {
                        ctx.Response.StatusCode = StatusCodes.Status403Forbidden;
                        return;
                    }
                }

                // Determine client identifier (prefer X-Forwarded-For then connection remote IP)
                string client = "unknown";
                if (ctx.Request.Headers.TryGetValue("X-Forwarded-For", out StringValues xff) && !string.IsNullOrWhiteSpace(xff))
                {
                    // X-Forwarded-For can contain a comma-separated list; take first
                    client = xff.ToString().Split(',')[0].Trim();
                }
                else if (ctx.Connection.RemoteIpAddress != null)
                {
                    client = ctx.Connection.RemoteIpAddress.ToString();
                }

                // rate limit only when no health token is configured OR even when token present? policy: always apply
                DateTime now = DateTime.UtcNow;
                (int Count, DateTime WindowStart) entry = rateLimitStore.AddOrUpdate(client,
                    _ => (1, now),
                    (_, state) =>
                    {
                        (int count, DateTime windowStart) = state;
                        if (now - windowStart > WINDOW)
                        {
                            // reset window
                            return (1, now);
                        }

                        return (count + 1, windowStart);
                    });

                if (entry.Count > LIMIT)
                {
                    ctx.Response.StatusCode = StatusCodes.Status429TooManyRequests;
                    ctx.Response.Headers.RetryAfter = "60"; // seconds
                    return;
                }

                ctx.Response.ContentType = "application/json";
                await ctx.Response.WriteAsync("{\"status\":\"ok\"}");
            });
        });

        return app;
    }
}