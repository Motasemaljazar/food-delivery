using System.ComponentModel.DataAnnotations;

namespace AdminDashboard.Entities;

public class RestaurantSettings
{
    public int Id { get; set; }

    [MaxLength(200)]
    public string RestaurantName { get; set; } = "";

    // Base64 or path (for local demo we store paths)
    public string? LogoUrl { get; set; }
    public string? CustomerSplashUrl { get; set; }
    public string? DriverSplashUrl { get; set; }

    // Optional marketing splash backgrounds (two-step splash in apps)
    public string? SplashBackground1Url { get; set; }
    public string? SplashBackground2Url { get; set; }

    [MaxLength(16)]
    public string PrimaryColorHex { get; set; } = "#D32F2F";

    [MaxLength(16)]
    public string SecondaryColorHex { get; set; } = "#111827";

    [MaxLength(16)]
    public string OffersColorHex { get; set; } = "#E11D48";

    [MaxLength(200)]
    public string WelcomeText { get; set; } = "أهلاً بك";

    /// <summary>
    /// JSON for the 3 onboarding slides shown in Customer App on first launch.
    /// Example:
    /// [{"title":"...","subtitle":"...","imageUrl":"/uploads/..."}, ...]
    /// </summary>
    public string? OnboardingJson { get; set; }

    /// <summary>
    /// JSON array of banner image URLs displayed at the very top of the Customer App home/menu screen.
    /// Example: ["/uploads/assets/banner/a.jpg","/uploads/assets/banner/b.jpg"]
    /// Managed from Admin Settings.
    /// </summary>
    public string? HomeBannersJson { get; set; }

    [MaxLength(64)]
    public string WorkHours { get; set; } = "";

    // Restaurant location
    public double RestaurantLat { get; set; }
    public double RestaurantLng { get; set; }

    // Operational controls
    public bool IsManuallyClosed { get; set; }

    [MaxLength(250)]
    public string ClosedMessage { get; set; } = "المطعم مغلق حالياً";

    // Background image for the closed screen in customer app
    public string? ClosedScreenImageUrl { get; set; }

    public decimal MinOrderAmount { get; set; }

    public DeliveryFeeType DeliveryFeeType { get; set; }
    public decimal DeliveryFeeValue { get; set; }

    /// <summary>
    /// سعر التوصيل لكل كيلومتر (عندما &gt; 0 يُحسب رسوم التوصيل = المسافة × هذا السعر).
    /// </summary>
    public decimal DeliveryFeePerKm { get; set; }

    /// <summary>
    /// إن كانت > 0 يتم جعل التوصيل مجانياً للطلبات التي مسافتها بالكيلومترات
    /// أقل أو تساوي هذه القيمة (DeliveryDistanceKm <= FreeDeliveryMaxKm).
    /// إذا كانت 0 أو أقل تعتبر الخاصية معطّلة.
    /// </summary>
    public double FreeDeliveryMaxKm { get; set; }

    [MaxLength(64)]
    public string SupportPhone { get; set; } = "";

    [MaxLength(64)]
    public string SupportWhatsApp { get; set; } = "";

    // Social links (editable from Admin Settings)
    [MaxLength(400)]
    public string? FacebookUrl { get; set; }

    [MaxLength(400)]
    public string? InstagramUrl { get; set; }

    [MaxLength(400)]
    public string? TelegramUrl { get; set; }

    public bool IsAcceptingOrders { get; set; }

    /// <summary>
    /// OSRM profile used for routing in Admin + Driver apps.
    /// Values: "driving" (default) or "foot".
    /// </summary>
    [MaxLength(16)]
    public string RoutingProfile { get; set; } = "driving";

    /// <summary>
    /// Used as a lightweight versioning mechanism for caching in apps.
    /// Updated whenever settings are saved from Admin.
    /// </summary>
    public DateTime UpdatedAtUtc { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Driver average speed (km/h) used for simple ETA estimation (no Directions API).
    /// Defaults are market-friendly: Bike=18, Car=30.
    /// </summary>
    public decimal DriverSpeedBikeKmH { get; set; } = 18m;
    public decimal DriverSpeedCarKmH { get; set; } = 30m;

    /// <summary>
    /// JSON for printer assignment: main, sub1, sub2 with optional category per sub.
    /// Example: {"mainPrinterName":"...","sub1PrinterName":"...","sub2PrinterName":"...","sub1CategoryId":2,"sub2CategoryId":3}
    /// </summary>
    public string? PrinterSettingsJson { get; set; }
}
