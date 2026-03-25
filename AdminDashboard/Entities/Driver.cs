using System.ComponentModel.DataAnnotations;

namespace AdminDashboard.Entities;

public class Driver
{
    public int Id { get; set; }

    [MaxLength(120)]
    public string Name { get; set; } = "";

    [MaxLength(40)]
    public string Phone { get; set; } = "";

    [MaxLength(16)]
    public string Pin { get; set; } = "1234";

    public VehicleType VehicleType { get; set; }

    public DriverStatus Status { get; set; }

    public string? PhotoUrl { get; set; }

    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}
