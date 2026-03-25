using System.ComponentModel.DataAnnotations;

namespace AdminDashboard.Entities;

public enum DeviceUserType
{
    Customer = 0,
    Driver = 1,
    Admin = 2
}

public class DeviceToken
{
    public int Id { get; set; }

    public DeviceUserType UserType { get; set; }
    public int UserId { get; set; }

    [MaxLength(512)]
    public string FcmToken { get; set; } = "";

    [MaxLength(32)]
    public string? Platform { get; set; } // android/web/ios

    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
    public DateTime LastSeenAtUtc { get; set; } = DateTime.UtcNow;
}
