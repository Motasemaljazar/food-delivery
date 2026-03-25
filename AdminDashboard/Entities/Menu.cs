using System.ComponentModel.DataAnnotations;

namespace AdminDashboard.Entities;

public class Category
{
    public int Id { get; set; }

    [MaxLength(120)]
    public string Name { get; set; } = "";

    // Optional image for category cards in Customer App.
    // Stored as relative URL under wwwroot (e.g. /uploads/assets/categories/...).
    [MaxLength(400)]
    public string? ImageUrl { get; set; }

    public bool IsActive { get; set; } = true;
    public int SortOrder { get; set; } = 0;

    public List<Product> Products { get; set; } = new();
}

public class Product
{
    public int Id { get; set; }

    [MaxLength(200)]
    public string Name { get; set; } = "";

    [MaxLength(2000)]
    public string? Description { get; set; }

    public decimal Price { get; set; }

    public bool IsActive { get; set; } = true;

    // Availability (can be out of stock temporarily)
    public bool IsAvailable { get; set; } = true;

    public int CategoryId { get; set; }
    public Category? Category { get; set; }

    public List<ProductImage> Images { get; set; } = new();

    public List<ProductVariant> Variants { get; set; } = new();
    public List<ProductAddon> Addons { get; set; } = new();
}

public class ProductImage
{
    public int Id { get; set; }
    public int ProductId { get; set; }
    public Product? Product { get; set; }

    // For local: store relative path or url
    [MaxLength(400)]
    public string Url { get; set; } = "";

    public int SortOrder { get; set; }

    // One image can be marked as primary; apps should display it first.
    public bool IsPrimary { get; set; }
}
