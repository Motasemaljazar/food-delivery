namespace AdminDashboard.Entities;

public class DriverTrackPoint
{
    public int Id { get; set; }
    public int DriverId { get; set; }

    // Optional: when a driver is actively delivering an order, we attach points to that order
    // so admin can render the actual polyline + compute distance.
    public int? OrderId { get; set; }

    public double Lat { get; set; }
    public double Lng { get; set; }
    public double SpeedMps { get; set; }
    public double HeadingDeg { get; set; }

    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}
