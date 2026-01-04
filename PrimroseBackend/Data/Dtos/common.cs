namespace PrimroseBackend.Data.Dtos;

public sealed record LoginDto(string Username, string Password);

public abstract record CreatePageDto(string Description, string Url);

public abstract record UpdatePageDto(string Description, string Url);