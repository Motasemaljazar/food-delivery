using System.ComponentModel.DataAnnotations;

namespace AdminDashboard.Entities;

// Optional delivery zones (free maps, no external routing)
// PolygonJson: GeoJSON-like array [[lat,lng],[lat,lng],...]
public class DeliveryZone
{
    public int Id { get; set; }

    [MaxLength(80)]
    public string Name { get; set; } = "";

    public decimal Fee { get; set; }
    public decimal? MinOrder { get; set; }
    public bool IsActive { get; set; } = true;
    public int SortOrder { get; set; } = 1;

    public string? PolygonJson { get; set; }
}
