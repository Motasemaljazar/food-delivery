using System.ComponentModel.DataAnnotations;

namespace AdminDashboard.Entities;

public class CustomerAddress
{
    public int Id { get; set; }

    public int CustomerId { get; set; }
    public Customer? Customer { get; set; }

    [MaxLength(40)]
    public string Title { get; set; } = "البيت";

    [MaxLength(300)]
    public string AddressText { get; set; } = "";

    public double Latitude { get; set; }
    public double Longitude { get; set; }

    [MaxLength(40)]
    public string? Building { get; set; }

    [MaxLength(20)]
    public string? Floor { get; set; }

    [MaxLength(20)]
    public string? Apartment { get; set; }

    [MaxLength(200)]
    public string? Notes { get; set; }

    public bool IsDefault { get; set; } = false;

    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAtUtc { get; set; } = DateTime.UtcNow;

    public string BuildFullText()
    {
        var parts = new List<string>();
        if (!string.IsNullOrWhiteSpace(Title)) parts.Add(Title.Trim());
        if (!string.IsNullOrWhiteSpace(AddressText)) parts.Add(AddressText.Trim());
        var extra = new List<string>();
        if (!string.IsNullOrWhiteSpace(Building)) extra.Add($"بناية {Building}");
        if (!string.IsNullOrWhiteSpace(Floor)) extra.Add($"طابق {Floor}");
        if (!string.IsNullOrWhiteSpace(Apartment)) extra.Add($"شقة {Apartment}");
        if (!string.IsNullOrWhiteSpace(Notes)) extra.Add($"ملاحظات: {Notes}");
        if (extra.Count > 0) parts.Add(string.Join(" - ", extra));
        return string.Join(" | ", parts);
    }
}
