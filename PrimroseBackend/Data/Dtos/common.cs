// ReSharper disable ClassNeverInstantiated.Global
namespace PrimroseBackend.Data.Dtos;

public record LoginDto(string Username, string Password);

public record CreatePageDto(string Description, string Url);

public record UpdatePageDto(string Description, string Url);
