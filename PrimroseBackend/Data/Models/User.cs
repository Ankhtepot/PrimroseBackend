using System.ComponentModel.DataAnnotations;

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
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
