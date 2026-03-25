using System.ComponentModel.DataAnnotations;

namespace AdminDashboard.Entities;

public class Order
{
    public int Id { get; set; }

    /// <summary>
    /// Client-generated UUID to prevent double-submit. Used for idempotent create within a short window.
    /// </summary>
    [MaxLength(64)]
    public string? IdempotencyKey { get; set; }

    public int CustomerId { get; set; }
    public Customer? Customer { get; set; }

    public int? DriverId { get; set; }
    public Driver? Driver { get; set; }

    public OrderStatus CurrentStatus { get; set; } = OrderStatus.New;

    // Cancel info (when cancelled)
    [MaxLength(80)]
    public string? CancelReasonCode { get; set; }

    // Optional reference to customer's saved address
    public int? CustomerAddressId { get; set; }
    public CustomerAddress? CustomerAddress { get; set; }

    // Delivery location for this order (may differ from customer's default)
    public double DeliveryLat { get; set; }
    public double DeliveryLng { get; set; }
    public string? DeliveryAddress { get; set; }

    /// <summary>
    /// نوع الطلب: "pickup" = استلام من الفرع، "delivery" = توصيل. إن كان null يُستنتج من الإحداثيات (0,0 = pickup).
    /// </summary>
    [MaxLength(20)]
    public string? OrderType { get; set; }

    [MaxLength(800)]
    public string? Notes { get; set; }

    public decimal Subtotal { get; set; }
    public decimal DeliveryFee { get; set; }

    // Total before cart-level discount (Subtotal + DeliveryFee)
    public decimal TotalBeforeDiscount { get; set; }

    // Cart-level discount applied on the total (like marketplaces)
    public decimal CartDiscount { get; set; }

    public decimal Total { get; set; }

    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Customer can edit the order until this UTC timestamp (usually CreatedAtUtc + 5 minutes).
    /// </summary>
    public DateTime? OrderEditableUntilUtc { get; set; }

    /// <summary>
    /// Set when the assigned driver explicitly confirms/starts the delivery (e.g., presses "بدء التوصيل").
    /// Reports should only count orders after this moment.
    /// </summary>
    public DateTime? DriverConfirmedAtUtc { get; set; }

    /// <summary>
    /// Set when driver marks the order as delivered.
    /// </summary>
    public DateTime? DeliveredAtUtc { get; set; }

    /// <summary>
    /// المسافة من المطعم إلى عنوان التوصيل (كم) عند إنشاء الطلب — تُستخدم لحساب رسوم التوصيل.
    /// </summary>
    public double DeliveryDistanceKm { get; set; }

    /// <summary>
    /// المسافة المقطوعة فعلياً أثناء التوصيل (كم).
    /// يتم تجميعها من نقاط التتبع GPS خلال حالة (مع السائق).
    /// </summary>
    public double DistanceKm { get; set; } = 0;

    // ETA fields (minutes) managed by admin
    public int? PrepEtaMinutes { get; set; }
    public int? DeliveryEtaMinutes { get; set; }
    public DateTime? ExpectedDeliveryAtUtc { get; set; }
    public DateTime? LastEtaUpdatedAtUtc { get; set; }

    public List<OrderItem> Items { get; set; } = new();
    public List<OrderStatusHistory> StatusHistory { get; set; } = new();
}

public class OrderItem
{
    public int Id { get; set; }

    public int OrderId { get; set; }
    public Order? Order { get; set; }

    public int ProductId { get; set; }
    public string ProductNameSnapshot { get; set; } = "";
    public decimal UnitPriceSnapshot { get; set; }
    public int Quantity { get; set; }

    [MaxLength(400)]
    public string? OptionsSnapshot { get; set; }
}

public class OrderStatusHistory
{
    public int Id { get; set; }
    public int OrderId { get; set; }
    public Order? Order { get; set; }

    public OrderStatus Status { get; set; }
    public DateTime ChangedAtUtc { get; set; } = DateTime.UtcNow;

    [MaxLength(20)]
    public string? ChangedByType { get; set; } // admin | customer | driver | system
    public int? ChangedById { get; set; }

    [MaxLength(80)]
    public string? ReasonCode { get; set; }

    [MaxLength(200)]
    public string? Comment { get; set; }
}
