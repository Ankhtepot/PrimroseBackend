using System.ComponentModel.DataAnnotations;

namespace PrimroseBackend.Data.Models;

public class Page
{
    [Key]
    public int Id { get; set; }
    [Required, MaxLength(256)]
    public string Description { get; set; } = "";
    [Required, MaxLength(256)]
    public string Url { get; set; } = "";
}