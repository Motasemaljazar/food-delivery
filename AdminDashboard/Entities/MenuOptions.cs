using System.ComponentModel.DataAnnotations;

namespace AdminDashboard.Entities;

public class ProductVariant
{
    public int Id { get; set; }
    public int ProductId { get; set; }
    public Product? Product { get; set; }

    [MaxLength(120)]
    public string Name { get; set; } = "";

    public decimal PriceDelta { get; set; }
    public bool IsActive { get; set; } = true;
    public int SortOrder { get; set; }
}

public class ProductAddon
{
    public int Id { get; set; }
    public int ProductId { get; set; }
    public Product? Product { get; set; }

    [MaxLength(120)]
    public string Name { get; set; } = "";

    public decimal Price { get; set; }
    public bool IsActive { get; set; } = true;
    public int SortOrder { get; set; }
}
