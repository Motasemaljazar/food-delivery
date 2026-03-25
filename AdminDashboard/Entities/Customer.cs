using System.ComponentModel.DataAnnotations;

namespace AdminDashboard.Entities;

public class Customer
{
    public int Id { get; set; }

    [MaxLength(120)]
    public string Name { get; set; } = "";

    [MaxLength(40)]
    public string Phone { get; set; } = "";

    // Firebase Auth (Email/Google)
    [MaxLength(128)]
    public string? FirebaseUid { get; set; }

    [MaxLength(180)]
    public string? Email { get; set; }

    // Default location
    public double DefaultLat { get; set; }
    public double DefaultLng { get; set; }
    public string? DefaultAddress { get; set; }

    // Last known GPS location (updated on app start + on order confirm)
    public double LastLat { get; set; }
    public double LastLng { get; set; }

    // Admin can block a customer from sending chat messages (spam/abuse).
    public bool IsChatBlocked { get; set; } = false;

    // Admin can block a customer from logging into the customer app entirely.
    public bool IsAppBlocked { get; set; } = false;

    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}
