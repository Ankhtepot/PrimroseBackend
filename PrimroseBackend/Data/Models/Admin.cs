using System.ComponentModel.DataAnnotations;
using PrimroseBackend.Shared;

namespace PrimroseBackend.Data.Models;

public class Admin
{
    [Key]
    public int Id { get; set; }
    [Required, MaxLength(256)]
    public string Username { get; set; } = null!;
    [Required, MaxLength(256)]
    public string PasswordHash { get; set; } = null!;
    public bool IsAdmin { get; set; } = false;
    [Required, MaxLength(128)]
    public string Role { get; set; } = ProjectConstants.Roles.Admin;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
