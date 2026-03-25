using System.ComponentModel.DataAnnotations;

namespace AdminDashboard.Entities;

public class AdminUser
{
    public int Id { get; set; }

    [MaxLength(200)]
    public string Email { get; set; } = "admin";

    // PBKDF2 hash (base64) + salt (base64)
    [MaxLength(400)]
    public string PasswordHash { get; set; } = "";

    [MaxLength(200)]
    public string PasswordSalt { get; set; } = "";

    public DateTime UpdatedAtUtc { get; set; } = DateTime.UtcNow;
}
