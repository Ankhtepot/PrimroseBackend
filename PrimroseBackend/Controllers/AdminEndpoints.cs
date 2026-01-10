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
using PrimroseBackend.Shared;
using System.Net; // for IPAddress

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

            bool passwordOk;
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

            // 1. Prepare a claims list
            List<Claim> claims =
            [
                new(ClaimTypes.Name, request.Username),
                new("IsAdmin", admin.IsAdmin.ToString().ToLower())
            ];

            // 2. Split roles from the string and add them as claims
            if (!string.IsNullOrWhiteSpace(admin.Role))
            {
                string[] roles = admin.Role.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                claims.AddRange(roles.Select(role => new Claim(ClaimTypes.Role, role)));
            }

            // 3. Create the token with the claims list
            JwtSecurityToken token = new(
                expires: DateTime.UtcNow.AddDays(1),
                signingCredentials: credentials,
                claims: claims
            );

            return Results.Ok(new {Token = new JwtSecurityTokenHandler().WriteToken(token)});
        });

        // === Admin Management CRUD ===
        app.MapGet("/api/admins", async (AppDbContext db) =>
                await db.Admins
                    .Select(a => new AdminResponseDto(a.Id, a.Username, a.Role, a.IsAdmin, a.CreatedAt))
                    .ToListAsync())
            .RequiredAdministrators(ProjectConstants.Roles.WebApp)
            .WithName("GetAdmins");

        app.MapPost("/api/admins", async (CreateAdminDto dto, AppDbContext db) =>
            {
                if (string.IsNullOrWhiteSpace(dto.Username) || string.IsNullOrWhiteSpace(dto.Password))
                    return Results.BadRequest("Username and Password are required");

                if (await db.Admins.AnyAsync(a => a.Username == dto.Username))
                    return Results.Conflict("Username already exists");

                Admin admin = new()
                {
                    Username = dto.Username,
                    PasswordHash = BCrypt.Net.BCrypt.HashPassword(dto.Password),
                    Role = dto.Role,
                    IsAdmin = dto.IsAdmin,
                    CreatedAt = DateTime.UtcNow
                };
                db.Admins.Add(admin);
                await db.SaveChangesAsync();
                return Results.Created($"/api/admins/{admin.Id}",
                    new AdminResponseDto(admin.Id, admin.Username, admin.Role, admin.IsAdmin, admin.CreatedAt));
            }).RequiredAdministrators(ProjectConstants.Roles.WebApp)
            .WithName("CreateAdmin");

        app.MapPut("/api/admins/{id:int}", async (int id, UpdateAdminDto dto, AppDbContext db, ClaimsPrincipal user) =>
            {
                if (string.IsNullOrWhiteSpace(dto.Username))
                    return Results.BadRequest("Username is required");

                Admin? admin = await db.Admins.FindAsync(id);
                if (admin == null) return Results.NotFound();

                // Prevent non-Admin users from modifying the core admin (ID 1)
                if (id == 1 && !user.IsInRole(ProjectConstants.Roles.Admin))
                {
                    return Results.Forbid();
                }

                admin.Username = dto.Username;
                admin.Role = dto.Role;
                admin.IsAdmin = dto.IsAdmin;
                if (!string.IsNullOrWhiteSpace(dto.Password))
                    admin.PasswordHash = BCrypt.Net.BCrypt.HashPassword(dto.Password);

                await db.SaveChangesAsync();
                return Results.Ok(new AdminResponseDto(admin.Id, admin.Username, admin.Role, admin.IsAdmin,
                    admin.CreatedAt));
            }).RequiredAdministrators(ProjectConstants.Roles.WebApp)
            .WithName("UpdateAdmin");

        app.MapDelete("/api/admins/{id:int}", async (int id, AppDbContext db) =>
            {
                Admin? admin = await db.Admins.FindAsync(id);
                if (admin == null) return Results.NotFound();
                if (admin.IsAdmin) return Results.BadRequest("Cannot delete admin account");
                if (admin.Id == 1) return Results.BadRequest($"Cannot delete {ProjectConstants.Roles.Admin} account");

                db.Admins.Remove(admin);
                await db.SaveChangesAsync();
                return Results.NoContent();
            }).RequiredAdministrators(ProjectConstants.Roles.WebApp)
            .WithName("DeleteAdmin");

        // Internal health endpoint: only accessible from loopback or from configured IPs (INTERNAL_HEALTH_ALLOWED_IPS)
        app.MapGet("/health/internal", (HttpContext ctx) =>
        {
            IConfiguration config = ctx.RequestServices.GetRequiredService<IConfiguration>();
            string? allowed = Environment.GetEnvironmentVariable("INTERNAL_HEALTH_ALLOWED_IPS") ?? config["INTERNAL_HEALTH_ALLOWED_IPS"]; 

            var remote = ctx.Connection.RemoteIpAddress;
            if (!IsAllowedInternalIp(remote, allowed))
            {
                return Results.StatusCode(StatusCodes.Status403Forbidden);
            }

            return Results.Ok(new { status = "ok" });
        }).AllowAnonymous();

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
                string? healthToken = Environment.GetEnvironmentVariable("PRIMROSE_HEALTH_TOKEN") 
                                      ?? config["PRIMROSE_HEALTH_TOKEN"]
                                      ?? Environment.GetEnvironmentVariable("HEALTH_TOKEN") 
                                      ?? config["HEALTH_TOKEN"];

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

        // Local helper for internal IP checks
        static bool IsAllowedInternalIp(IPAddress? remoteIp, string? allowedList)
        {
            if (remoteIp == null) return false;
            if (IPAddress.IsLoopback(remoteIp)) return true; // always allow loopback

            if (string.IsNullOrWhiteSpace(allowedList))
            {
                // If no explicit allowed list is provided, do NOT allow non-loopback addresses
                return false;
            }

            var parts = allowedList.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            foreach (var part in parts)
            {
                if (IPAddress.TryParse(part, out var ip))
                {
                    if (ip.Equals(remoteIp)) return true;
                }
                // Note: CIDR ranges are intentionally not parsed here to keep this helper minimal and deterministic.
            }

            return false;
        }
    }
}

