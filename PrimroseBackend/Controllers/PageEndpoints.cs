using Microsoft.EntityFrameworkCore;
using OtpNet;
using PrimroseBackend.Data;
using PrimroseBackend.Data.Dtos;
using PrimroseBackend.Data.Models;
using PrimroseBackend.Shared;

namespace PrimroseBackend.Controllers;

public static class PageEndpoints
{
    public static WebApplication MapPageEndpoints(this WebApplication app)
    {
        app.MapGet("/api/pages", async (AppDbContext db, IConfiguration config, HttpContext ctx) =>
            {
                // TOTP Secret (dev: env, prod: secret file)
                string? secret = Environment.GetEnvironmentVariable("SharedSecret") ?? config["SharedSecret"];

                if (string.IsNullOrEmpty(secret))
                    return Results.Unauthorized();

                byte[]? totpSecret = Base32Encoding.ToBytes(secret);
                Totp totp = new(totpSecret);

                string? authHeader = ctx.Request.Headers["X-App-Auth"].FirstOrDefault();
                if (!int.TryParse(authHeader, out int code) ||
                    !totp.VerifyTotp(code.ToString(), out _, new VerificationWindow(1, 1)))
                    return Results.Unauthorized();

                List<Page> pages = await db.Pages.ToListAsync();
                return Results.Ok(pages);
            })
            .WithName("GetPages");

// === ADMIN (JWT) ===
        

        app.MapGet("/api/pages/admin", async (AppDbContext db) =>
                await db.Pages.ToListAsync())
            .RequiredAdministrators(ProjectConstants.Roles.WebApp)
            .WithName("GetPagesAdmin");

        app.MapPost("/api/pages", async (CreatePageDto dto, AppDbContext db) =>
            {
                if (string.IsNullOrWhiteSpace(dto.Description) || string.IsNullOrWhiteSpace(dto.Url))
                    return Results.BadRequest("Description and URL are required");

                Page page = new() { Description = dto.Description, Url = dto.Url };
                db.Pages.Add(page);
                await db.SaveChangesAsync();
                return Results.Created($"/api/pages/{page.Id}", page);
            }).RequiredAdministrators(ProjectConstants.Roles.WebApp)
            .WithName("CreatePage");

        app.MapPut("/api/pages/{id:int}", async (int id, UpdatePageDto dto, AppDbContext db) =>
            {
                if (string.IsNullOrWhiteSpace(dto.Description) || string.IsNullOrWhiteSpace(dto.Url))
                    return Results.BadRequest("Description and URL are required");

                Page? page = await db.Pages.FindAsync(id);
                if (page == null) return Results.NotFound();
                
                page.Description = dto.Description;
                page.Url = dto.Url;
                await db.SaveChangesAsync();
                return Results.Ok(page);
            }).RequiredAdministrators(ProjectConstants.Roles.WebApp)
            .WithName("UpdatePage");

        app.MapDelete("/api/pages/{id:int}", async (int id, AppDbContext db) =>
            {
                Page? page = await db.Pages.FindAsync(id);
                if (page == null) return Results.NotFound();

                db.Pages.Remove(page);
                await db.SaveChangesAsync();
                return Results.NoContent();
            }).RequiredAdministrators(ProjectConstants.Roles.WebApp)
            .WithName("DeletePage");

        return app;
    }
}