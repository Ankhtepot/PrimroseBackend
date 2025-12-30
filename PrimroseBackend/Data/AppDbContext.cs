using Microsoft.EntityFrameworkCore;
using PrimroseBackend.Data.Models;

namespace PrimroseBackend.Data;

public class AppDbContext : DbContext
{
    public DbSet<Page> Pages { get; set; } = null!;
    
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }
}