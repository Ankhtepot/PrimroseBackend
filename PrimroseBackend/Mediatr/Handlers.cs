using MediatR;
using Microsoft.EntityFrameworkCore;
using PrimroseBackend.Data;
using PrimroseBackend.Data.Models;

namespace PrimroseBackend.Mediatr;

// === HANDLERS ===
public class GetPagesQueryHandler(AppDbContext ctx) : IRequestHandler<GetPagesQuery, List<Page>>
{
    public Task<List<Page>> Handle(GetPagesQuery req, CancellationToken ct) => ctx.Pages.ToListAsync(ct);
}

public class CreatePageCommandHandler(AppDbContext ctx) : IRequestHandler<CreatePageCommand, Page>
{
    public async Task<Page> Handle(CreatePageCommand cmd, CancellationToken ct)
    {
        Page page = new Page {Description = cmd.Description, Url = cmd.Url};
        ctx.Pages.Add(page);
        await ctx.SaveChangesAsync(ct);
        return page;
    }
}

public class UpdatePageCommandHandler(AppDbContext ctx) : IRequestHandler<UpdatePageCommand, Page>
{
    public async Task<Page> Handle(UpdatePageCommand cmd, CancellationToken ct)
    {
        Page page = await ctx.Pages.FindAsync([cmd.Id], ct)
                    ?? throw new Exception("Page not found");
        page.Description = cmd.Description;
        page.Url = cmd.Url;
        await ctx.SaveChangesAsync(ct);
        return page;
    }
}