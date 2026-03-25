using System.ComponentModel.DataAnnotations;

namespace AdminDashboard.Entities;

public enum NotificationUserType
{
    Admin = 1,
    Customer = 2,
    Driver = 3
}

public class Notification
{
    public int Id { get; set; }

    public NotificationUserType UserType { get; set; }
    public int? UserId { get; set; } // null for Admin broadcast

    [MaxLength(120)]
    public string Title { get; set; } = "";

    [MaxLength(400)]
    public string Body { get; set; } = "";

    public int? RelatedOrderId { get; set; }
    public bool IsRead { get; set; }
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}
