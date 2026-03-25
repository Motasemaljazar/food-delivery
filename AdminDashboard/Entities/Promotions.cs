using System.ComponentModel.DataAnnotations;

namespace AdminDashboard.Entities;

/// <summary>
/// Offers system only (no coupons/discounts).
/// </summary>
public class Offer
{
    public int Id { get; set; }

    [MaxLength(200)]
    public string Title { get; set; } = "";

    [MaxLength(2000)]
    public string? Description { get; set; }

    // Uploaded image (optional)
    public string? ImageUrl { get; set; }

    // Optional pricing (independent offer item)
    public decimal? PriceBefore { get; set; }
    public decimal? PriceAfter { get; set; }

    // Optional code shown to the customer (not a coupons/discounts system)
    [MaxLength(64)]
    public string? Code { get; set; }

    public DateTime? StartsAtUtc { get; set; }
    public DateTime? EndsAtUtc { get; set; }

    public bool IsActive { get; set; } = true;
}

public class OfferProduct
{
    public int Id { get; set; }
    public int OfferId { get; set; }
    public int ProductId { get; set; }
}

/// <summary>
/// Optional mapping: Offer -> Categories (to support filtering/browsing by category).
/// </summary>
public class OfferCategory
{
    public int Id { get; set; }
    public int OfferId { get; set; }
    public int CategoryId { get; set; }
}

public enum DiscountTargetType
{
    Product = 1,
    Category = 2,
    Cart = 3
}

public enum DiscountValueType
{
    Percent = 1,
    Fixed = 2
}

/// <summary>
/// Market-style discounts (no payment system).
/// Applies to product/category (affects unit prices) and cart (affects order total).
/// </summary>
public class Discount
{
    public int Id { get; set; }

    [MaxLength(120)]
    public string Title { get; set; } = "خصم";

    public DiscountTargetType TargetType { get; set; }

    /// <summary>
    /// ProductId or CategoryId depending on TargetType. Null for Cart discount.
    /// </summary>
    public int? TargetId { get; set; }

    public DiscountValueType ValueType { get; set; } = DiscountValueType.Percent;

    /// <summary>
    /// 0..100 (used when ValueType = Percent)
    /// </summary>
    public decimal? Percent { get; set; }

    /// <summary>
    /// Fixed amount in the currency (used when ValueType = Fixed)
    /// </summary>
    public decimal? Amount { get; set; }

    /// <summary>
    /// For Cart discount only.
    /// </summary>
    public decimal? MinOrderAmount { get; set; }

    public bool IsActive { get; set; } = true;

    public DateTime? StartsAtUtc { get; set; }
    public DateTime? EndsAtUtc { get; set; }

    [MaxLength(30)]
    public string? BadgeText { get; set; } // e.g. "خصم 20%"
}
