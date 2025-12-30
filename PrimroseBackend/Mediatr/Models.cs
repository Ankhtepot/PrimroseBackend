using MediatR;
using PrimroseBackend.Data.Models;

namespace PrimroseBackend.Mediatr;

public record GetPagesQuery : IRequest<List<Page>>;

public record CreatePageCommand(string Description, string Url) : IRequest<Page>;

public record UpdatePageCommand(int Id, string Description, string Url) : IRequest<Page>;