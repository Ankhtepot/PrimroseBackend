using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using MediatR;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using OtpNet;
using PrimroseBackend.Data;
using PrimroseBackend.Data.Dtos;
using PrimroseBackend.Data.Models;
using PrimroseBackend.Mediatr;

namespace PrimroseBackend.Controllers;

public static class PageEndpoints
{
    public static WebApplication MapPageEndpoints(this WebApplication app)
    {
        app.MapGet("/api/pages", async (IMediator mediator, IConfiguration config, HttpContext ctx) =>
            {
                // TOTP Secret (dev: env, prod: secret file)
                string secretPath = "/run/secrets/shared_secret";
                string secret = File.Exists(secretPath)
                    ? await File.ReadAllTextAsync(secretPath)
                    : config["SharedSecret"] ?? "";

                if (string.IsNullOrEmpty(secret))
                    return Results.Unauthorized();

                byte[]? totpSecret = Base32Encoding.ToBytes(secret);
                Totp totp = new(totpSecret);

                string? authHeader = ctx.Request.Headers["X-App-Auth"].FirstOrDefault();
                if (!int.TryParse(authHeader, out int code) ||
                    !totp.VerifyTotp(code.ToString(), out _, new VerificationWindow(1, 1)))
                    return Results.Unauthorized();

                List<Page> pages = await mediator.Send(new GetPagesQuery());
                return Results.Ok(pages);
            })
            .WithName("GetPages");

// === ADMIN (JWT) ===
        app.MapPost("/api/auth/login", async (LoginDto request, AppDbContext db, IConfiguration config) =>
        {
            if (string.IsNullOrWhiteSpace(request.Username) || string.IsNullOrWhiteSpace(request.Password))
                return Results.Unauthorized();

            var admin = await db.Admins.SingleOrDefaultAsync(a => a.Username == request.Username);
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

            // get jwt secret from environment (set at startup from docker secrets) or config
            string? jwtSecret = Environment.GetEnvironmentVariable("JwtSecret") ?? config["JwtSecret"];
            if (string.IsNullOrWhiteSpace(jwtSecret))
                throw new InvalidOperationException("JwtSecret is missing");

            SymmetricSecurityKey key = new(Encoding.UTF8.GetBytes(jwtSecret));
            SigningCredentials creds = new(key, SecurityAlgorithms.HmacSha256);

            JwtSecurityToken token = new(
                expires: DateTime.Now.AddDays(7),
                signingCredentials: creds,
                claims: new[] { new Claim(ClaimTypes.Name, request.Username) }
            );

            return Results.Ok(new { Token = new JwtSecurityTokenHandler().WriteToken(token) });
        });

        app.MapGet("/api/pages/admin", async (IMediator mediator) =>
                await mediator.Send(new GetPagesQuery()))
            .RequireAuthorization()
            .WithName("GetPagesAdmin");

        app.MapPost("/api/pages", async (CreatePageCommand cmd, IMediator mediator) =>
            {
                Page page = await mediator.Send(cmd);
                return Results.Created($"/api/pages/{page.Id}", page);
            }).RequireAuthorization()
            .WithName("CreatePage");

        app.MapPut("/api/pages/{id:int}", async (int id, UpdatePageCommand cmd, IMediator mediator) =>
            {
                if (cmd.Id != id) return Results.BadRequest();
                Page page = await mediator.Send(cmd);
                return Results.Ok(page);
            }).RequireAuthorization()
            .WithName("UpdatePage");
        return app;
    }
}