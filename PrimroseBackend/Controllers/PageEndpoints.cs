using MediatR;
using OtpNet;
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
                string? secret = Environment.GetEnvironmentVariable("SharedSecret") ?? config["SharedSecret"];

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