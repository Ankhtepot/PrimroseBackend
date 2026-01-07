// ReSharper disable ClassNeverInstantiated.Global
namespace PrimroseBackend.Data.Dtos;

public record LoginDto(string Username, string Password);

public record CreatePageDto(string Description, string Url);

public record UpdatePageDto(string Description, string Url);

public record CreateAdminDto(string Username, string Password, string Role, bool IsAdmin);

public record UpdateAdminDto(string Username, string? Password, string Role, bool IsAdmin);

public record AdminResponseDto(int Id, string Username, string Role, bool IsAdmin, DateTime CreatedAt);
