using AdminDashboard.Data;
using AdminDashboard.Entities;
using AdminDashboard.Hubs;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;

namespace AdminDashboard.Controllers;

[ApiController]
[Route("api/customer")]
public class CustomerController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IHubContext<NotifyHub> _hub;
    private readonly NotificationService _notifications;
    private readonly AdminDashboard.Services.FirebaseAdminService _firebase;

    public CustomerController(AppDbContext db, IHubContext<NotifyHub> hub, NotificationService notifications, AdminDashboard.Services.FirebaseAdminService firebase)
    {
        _db = db;
        _hub = hub;
        _notifications = notifications;
        _firebase = firebase;
    }

    private static double HaversineKm(double lat1, double lon1, double lat2, double lon2)
    {
        const double R = 6371.0;
        double dLat = (lat2 - lat1) * Math.PI / 180.0;
        double dLon = (lon2 - lon1) * Math.PI / 180.0;
        double a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                   Math.Cos(lat1 * Math.PI / 180.0) * Math.Cos(lat2 * Math.PI / 180.0) *
                   Math.Sin(dLon / 2) * Math.Sin(dLon / 2);
        double c = 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
        return R * c;
    }

    public record FirebaseSessionRequest(string IdToken);
    public record FirebaseRegisterRequest(string IdToken, string Name, string Phone, double Lat, double Lng, string? Address);

    /// <summary>
    /// Firebase Auth session: if customer exists for this Firebase UID return it,
    /// otherwise tell the app to complete profile.
    /// </summary>
    [HttpPost("firebase/session")]
    public async Task<IActionResult> FirebaseSession(FirebaseSessionRequest req)
    {
        var token = (req.IdToken ?? "").Trim();
        if (string.IsNullOrWhiteSpace(token)) return BadRequest(new { error = "missingToken" });

        var verified = await _firebase.VerifyIdTokenAsync(token);
        if (verified == null) return Unauthorized(new { error = "invalidToken" });

        var uid = verified.Uid;
        var email = verified.Claims.ContainsKey("email") ? verified.Claims["email"]?.ToString() : null;
        var name = verified.Claims.ContainsKey("name") ? verified.Claims["name"]?.ToString() : null;

        var customer = await _db.Customers.AsNoTracking().FirstOrDefaultAsync(c => c.FirebaseUid == uid);
        if (customer == null)
            return Ok(new { requiresProfile = true, email, name });

        if (customer.IsAppBlocked)
            return StatusCode(403, new { error = "customer_blocked", message = "تم منعك من الدخول" });

        return Ok(new
        {
            customer.Id,
            customer.Name,
            customer.Phone,
            customer.DefaultLat,
            customer.DefaultLng,
            customer.DefaultAddress,
            email = customer.Email ?? email,
        });
    }

    /// <summary>
    /// Firebase Auth register/update: upsert customer using Firebase UID.
    /// Name + default location are mandatory.
    /// </summary>
    [HttpPost("firebase/register")]
    public async Task<IActionResult> FirebaseRegister(FirebaseRegisterRequest req)
    {
        var token = (req.IdToken ?? "").Trim();
        if (string.IsNullOrWhiteSpace(token)) return BadRequest(new { error = "missingToken" });

        var verified = await _firebase.VerifyIdTokenAsync(token);
        if (verified == null) return Unauthorized(new { error = "invalidToken" });

        if (string.IsNullOrWhiteSpace(req.Name)) return BadRequest(new { error = "الاسم مطلوب" });
        if (string.IsNullOrWhiteSpace(req.Phone)) return BadRequest(new { error = "رقم الهاتف مطلوب" });
        if (req.Lat == 0 && req.Lng == 0) return BadRequest(new { error = "الموقع مطلوب" });

        var uid = verified.Uid;
        var email = verified.Claims.ContainsKey("email") ? verified.Claims["email"]?.ToString() : null;

        var customer = await _db.Customers.FirstOrDefaultAsync(c => c.FirebaseUid == uid);
        if (customer == null)
        {
            customer = new Customer
            {
                Name = req.Name.Trim(),
                Phone = req.Phone.Trim(),
                FirebaseUid = uid,
                Email = email,
                DefaultLat = req.Lat,
                DefaultLng = req.Lng,
                LastLat = req.Lat,
                LastLng = req.Lng,
                DefaultAddress = req.Address
            };
            _db.Customers.Add(customer);
        }
        else
        {
            if (customer.IsAppBlocked)
                return StatusCode(403, new { error = "customer_blocked", message = "تم منعك من الدخول" });
            customer.Name = req.Name.Trim();
            customer.Phone = req.Phone.Trim();
            customer.Email = email ?? customer.Email;
            customer.DefaultLat = req.Lat;
            customer.DefaultLng = req.Lng;
            customer.LastLat = req.Lat;
            customer.LastLng = req.Lng;
            customer.DefaultAddress = req.Address;
        }

        await _db.SaveChangesAsync();
        return Ok(new { customer.Id, customer.Name, customer.Phone, customer.DefaultLat, customer.DefaultLng, customer.DefaultAddress });
    }

    public record RegisterRequest(string Name, string Phone, double Lat, double Lng, string? Address);

    [HttpPost("register")]
    public async Task<IActionResult> Register(RegisterRequest req)
    {
        var customer = await _db.Customers.FirstOrDefaultAsync(c => c.Phone == req.Phone);
        if (customer != null && customer.IsAppBlocked)
            return StatusCode(403, new { error = "customer_blocked", message = "تم منعك من الدخول" });
        if (customer == null)
        {
            customer = new Customer
            {
                Name = req.Name,
                Phone = req.Phone,
                DefaultLat = req.Lat,
                DefaultLng = req.Lng,
                LastLat = req.Lat,
                LastLng = req.Lng,
                DefaultAddress = req.Address
            };
            _db.Customers.Add(customer);
        }
        else
        {
            customer.Name = req.Name;
            customer.DefaultLat = req.Lat;
            customer.DefaultLng = req.Lng;
            customer.LastLat = req.Lat;
            customer.LastLng = req.Lng;
            customer.DefaultAddress = req.Address;
        }

        await _db.SaveChangesAsync();
        return Ok(new { customer.Id, customer.Name, customer.Phone, customer.DefaultLat, customer.DefaultLng, customer.DefaultAddress });
    }

    

// -----------------------------
// Customer Saved Addresses (SRS)
// -----------------------------
public record AddressDto(
    int Id,
    string Title,
    string AddressText,
    double Latitude,
    double Longitude,
    string? Building,
    string? Floor,
    string? Apartment,
    string? Notes,
    bool IsDefault,
    DateTime CreatedAtUtc,
    DateTime UpdatedAtUtc);

[HttpGet("addresses/{customerId:int}")]
public async Task<IActionResult> GetAddresses(int customerId)
{
    var list = await _db.CustomerAddresses.AsNoTracking()
        .Where(a => a.CustomerId == customerId)
        .OrderByDescending(a => a.IsDefault)
        .ThenByDescending(a => a.UpdatedAtUtc)
        .Select(a => new AddressDto(a.Id, a.Title, a.AddressText, a.Latitude, a.Longitude, a.Building, a.Floor, a.Apartment, a.Notes, a.IsDefault, a.CreatedAtUtc, a.UpdatedAtUtc))
        .ToListAsync();
    return Ok(list);
}

public record CreateAddressReq(
    int CustomerId,
    string Title,
    string AddressText,
    double Latitude,
    double Longitude,
    string? Building,
    string? Floor,
    string? Apartment,
    string? Notes,
    bool SetDefault);

[HttpPost("addresses")]
public async Task<IActionResult> CreateAddress(CreateAddressReq req)
{
    var customer = await _db.Customers.FindAsync(req.CustomerId);
    if (customer == null) return NotFound(new { error = "customer_not_found" });

    var a = new CustomerAddress
    {
        CustomerId = req.CustomerId,
        Title = string.IsNullOrWhiteSpace(req.Title) ? "البيت" : req.Title.Trim(),
        AddressText = (req.AddressText ?? "").Trim(),
        Latitude = req.Latitude,
        Longitude = req.Longitude,
        Building = string.IsNullOrWhiteSpace(req.Building) ? null : req.Building.Trim(),
        Floor = string.IsNullOrWhiteSpace(req.Floor) ? null : req.Floor.Trim(),
        Apartment = string.IsNullOrWhiteSpace(req.Apartment) ? null : req.Apartment.Trim(),
        Notes = string.IsNullOrWhiteSpace(req.Notes) ? null : req.Notes.Trim(),
        IsDefault = false,
        CreatedAtUtc = DateTime.UtcNow,
        UpdatedAtUtc = DateTime.UtcNow
    };

    // If first address, make it default automatically.
    var hasAny = await _db.CustomerAddresses.AsNoTracking().AnyAsync(x => x.CustomerId == req.CustomerId);
    if (!hasAny) a.IsDefault = true;
    if (req.SetDefault) a.IsDefault = true;

    if (a.IsDefault)
    {
        var others = await _db.CustomerAddresses.Where(x => x.CustomerId == req.CustomerId && x.IsDefault).ToListAsync();
        foreach (var o in others) o.IsDefault = false;
    }

    _db.CustomerAddresses.Add(a);
    await _db.SaveChangesAsync();

    return Ok(new AddressDto(a.Id, a.Title, a.AddressText, a.Latitude, a.Longitude, a.Building, a.Floor, a.Apartment, a.Notes, a.IsDefault, a.CreatedAtUtc, a.UpdatedAtUtc));
}

public record UpdateAddressReq(
    int CustomerId,
    string Title,
    string AddressText,
    double Latitude,
    double Longitude,
    string? Building,
    string? Floor,
    string? Apartment,
    string? Notes);

[HttpPut("addresses/{id:int}")]
public async Task<IActionResult> UpdateAddress(int id, UpdateAddressReq req)
{
    var a = await _db.CustomerAddresses.FirstOrDefaultAsync(x => x.Id == id && x.CustomerId == req.CustomerId);
    if (a == null) return NotFound(new { error = "address_not_found" });

    a.Title = string.IsNullOrWhiteSpace(req.Title) ? a.Title : req.Title.Trim();
    a.AddressText = (req.AddressText ?? "").Trim();
    a.Latitude = req.Latitude;
    a.Longitude = req.Longitude;
    a.Building = string.IsNullOrWhiteSpace(req.Building) ? null : req.Building.Trim();
    a.Floor = string.IsNullOrWhiteSpace(req.Floor) ? null : req.Floor.Trim();
    a.Apartment = string.IsNullOrWhiteSpace(req.Apartment) ? null : req.Apartment.Trim();
    a.Notes = string.IsNullOrWhiteSpace(req.Notes) ? null : req.Notes.Trim();
    a.UpdatedAtUtc = DateTime.UtcNow;

    await _db.SaveChangesAsync();
    return Ok(new AddressDto(a.Id, a.Title, a.AddressText, a.Latitude, a.Longitude, a.Building, a.Floor, a.Apartment, a.Notes, a.IsDefault, a.CreatedAtUtc, a.UpdatedAtUtc));
}

[HttpDelete("addresses/{id:int}")]
public async Task<IActionResult> DeleteAddress(int id, [FromQuery] int customerId)
{
    var a = await _db.CustomerAddresses.FirstOrDefaultAsync(x => x.Id == id && x.CustomerId == customerId);
    if (a == null) return NotFound(new { error = "address_not_found" });

    var wasDefault = a.IsDefault;
    _db.CustomerAddresses.Remove(a);
    await _db.SaveChangesAsync();

    if (wasDefault)
    {
        var next = await _db.CustomerAddresses.FirstOrDefaultAsync(x => x.CustomerId == customerId);
        if (next != null)
        {
            next.IsDefault = true;
            next.UpdatedAtUtc = DateTime.UtcNow;
            await _db.SaveChangesAsync();
        }
    }

    return Ok(new { ok = true });
}

[HttpPost("addresses/{id:int}/set-default")]
public async Task<IActionResult> SetDefaultAddress(int id, [FromQuery] int customerId)
{
    var a = await _db.CustomerAddresses.FirstOrDefaultAsync(x => x.Id == id && x.CustomerId == customerId);
    if (a == null) return NotFound(new { error = "address_not_found" });

    var others = await _db.CustomerAddresses.Where(x => x.CustomerId == customerId && x.Id != id && x.IsDefault).ToListAsync();
    foreach (var o in others) o.IsDefault = false;

    a.IsDefault = true;
    a.UpdatedAtUtc = DateTime.UtcNow;

    await _db.SaveChangesAsync();
    return Ok(new { ok = true });
}

    public record OrderItemReq(int ProductId, int Quantity, string? OptionsSnapshot);
    public record CreateOrderRequest(
        int CustomerId,
        string IdempotencyKey,
        List<OrderItemReq> Items,
        string? Notes,
        int? AddressId,
        double DeliveryLat,
        double DeliveryLng,
        string? DeliveryAddress,
        string? OrderType);


    [HttpPost("orders")]
    public async Task<IActionResult> CreateOrder(CreateOrderRequest req)
    {
        // Enforce restaurant closed state.
        // If there is no row yet (fresh DB), we fall back to safe defaults.
        var settings = await _db.RestaurantSettings.AsNoTracking().FirstOrDefaultAsync()
            ?? new RestaurantSettings
            {
                MinOrderAmount = 0,
                DeliveryFeeType = DeliveryFeeType.Fixed,
                DeliveryFeeValue = 0,
                IsAcceptingOrders = true,
                IsManuallyClosed = false,
                ClosedMessage = "المطعم مغلق حالياً"
            };

        if (settings.IsManuallyClosed)
            return BadRequest(new { error = "restaurant_closed", message = string.IsNullOrWhiteSpace(settings.ClosedMessage) ? "المطعم مغلق حالياً" : settings.ClosedMessage });

        var customer = await _db.Customers.FindAsync(req.CustomerId);
        if (customer == null) return NotFound(new { error = "الزبون غير موجود" });

        if (customer.IsAppBlocked)
            return StatusCode(403, new { error = "customer_blocked", message = "تم منعك من الدخول" });

        CustomerAddress? addr = null;
        if (req.AddressId.HasValue)
        {
            addr = await _db.CustomerAddresses.AsNoTracking().FirstOrDefaultAsync(a => a.Id == req.AddressId.Value && a.CustomerId == req.CustomerId);
            if (addr == null) return BadRequest(new { error = "address_not_found", message = "العنوان المختار غير موجود" });
        }


        // Rating is OPTIONAL (market requirement): do NOT block new orders.
        // The app can still fetch /api/customer/pending-rating/{customerId} to suggest rating in a friendly dialog.

// Idempotency (prevents double submit). Client must send UUID.
        var key = (req.IdempotencyKey ?? "").Trim();
        if (string.IsNullOrWhiteSpace(key))
            return BadRequest(new { error = "idempotency_required", message = "تعذر إرسال الطلب. حاول مجدداً." });

        var window = DateTime.UtcNow.AddMinutes(-5);
        var existing = await _db.Orders.AsNoTracking()
            .Where(o => o.CustomerId == req.CustomerId && o.IdempotencyKey == key && o.CreatedAtUtc >= window)
            .OrderByDescending(o => o.Id)
            .Select(o => new { o.Id })
            .FirstOrDefaultAsync();
        if (existing != null)
            return Ok(new { id = existing.Id, alreadyCreated = true });

        // استلام من الفرع: orderType = "pickup" أو عنوان "استلام من الفرع" أو (0,0) بدون عنوان محفوظ — حتى يمكن تأكيد الطلب مباشرة دون مطالبة بموقع.
        var isPickup = string.Equals(req.OrderType, "pickup", StringComparison.OrdinalIgnoreCase)
            || string.Equals(req.DeliveryAddress?.Trim(), "استلام من الفرع", StringComparison.OrdinalIgnoreCase)
            || (addr == null && req.DeliveryLat == 0 && req.DeliveryLng == 0);

        double finalLat, finalLng;
        string? finalAddress;
        if (isPickup)
        {
            finalLat = 0;
            finalLng = 0;
            finalAddress = "استلام من الفرع";
        }
        else
        {
            if (addr == null && req.DeliveryLat == 0 && req.DeliveryLng == 0)
                return BadRequest(new { error = "gps_required", message = "يجب اختيار عنوان أو تفعيل الموقع لإرسال الطلب" });
            finalLat = (addr != null) ? addr.Latitude : req.DeliveryLat;
            finalLng = (addr != null) ? addr.Longitude : req.DeliveryLng;
            finalAddress = (addr != null) ? addr.BuildFullText() : (req.DeliveryAddress ?? customer.DefaultAddress);
        }


        // Items may contain:
        // - Product items: ProductId > 0
        // - Offer items: ProductId < 0 (negative offerId)
        var productIds = req.Items.Where(i => i.ProductId > 0).Select(i => i.ProductId).Distinct().ToList();
        var offerIds = req.Items.Where(i => i.ProductId < 0).Select(i => Math.Abs(i.ProductId)).Distinct().ToList();

        // Offers may be linked to products (optional) so we can reuse product variants/addons.
        // This enables "عرض مثل المنيو" (اختيارات + إضافات) داخل تطبيق الزبون.
        var offerProductLinks = (offerIds.Count == 0)
            ? new List<OfferProduct>()
            : await _db.OfferProducts.AsNoTracking().Where(x => offerIds.Contains(x.OfferId)).ToListAsync();
        var offerPrimaryProduct = offerProductLinks
            .GroupBy(x => x.OfferId)
            .ToDictionary(g => g.Key, g => g.Select(x => x.ProductId).FirstOrDefault());

        var linkedProductIds = offerProductLinks.Select(x => x.ProductId).Distinct().ToList();
        foreach (var pid in linkedProductIds)
            if (!productIds.Contains(pid)) productIds.Add(pid);

        var products = (productIds.Count == 0)
            ? new List<Product>()
            : await _db.Products.Where(p => productIds.Contains(p.Id) && p.IsActive).ToListAsync();
        if (products.Count != productIds.Count) return BadRequest(new { error = "بعض الأصناف غير صحيحة" });

        var offers = (offerIds.Count == 0)
            ? new List<Offer>()
            : await _db.Offers.AsNoTracking().Where(o => offerIds.Contains(o.Id) && o.IsActive).ToListAsync();
        if (offers.Count != offerIds.Count) return BadRequest(new { error = "بعض العروض غير صحيحة" });

        // Active discounts (market-style) - applied automatically (no coupon codes)
        var now = DateTime.UtcNow;
        var discounts = await _db.Discounts.AsNoTracking()
            .Where(d => d.IsActive
                        && d.TargetType != DiscountTargetType.Cart // cart coupons disabled for SRDS
                        && (d.StartsAtUtc == null || d.StartsAtUtc <= now)
                        && (d.EndsAtUtc == null || d.EndsAtUtc >= now))
            .ToListAsync();

        decimal ApplyDiscount(decimal original, Discount d)
        {
            if (original <= 0) return 0;
            decimal v = original;
            if (d.ValueType == DiscountValueType.Percent)
            {
                var p = d.Percent ?? 0;
                v = original - (original * p / 100m);
            }
            else
            {
                var a = d.Amount ?? 0;
                v = original - a;
            }
            if (v < 0) v = 0;
            return Math.Round(v, 2);
        }

        (decimal finalBasePrice, string? badgeText, decimal? percent) BestDiscountForProduct(int productId, int categoryId, decimal original)
        {
            if (discounts.Count == 0) return (original, null, null);
            var prod = discounts.Where(x => x.TargetType == DiscountTargetType.Product && x.TargetId == productId).ToList();
            var cat = discounts.Where(x => x.TargetType == DiscountTargetType.Category && x.TargetId == categoryId).ToList();
            Discount? best = null;
            decimal bestFinal = original;
            foreach (var d in prod.Concat(cat))
            {
                var f = ApplyDiscount(original, d);
                if (f < bestFinal)
                {
                    bestFinal = f;
                    best = d;
                }
            }
            if (best == null || bestFinal >= original) return (original, null, null);
            decimal? pct = null;
            if (best.ValueType == DiscountValueType.Percent) pct = best.Percent;
            else if (original > 0) pct = Math.Round((1m - (bestFinal / original)) * 100m, 0);
            var badge = !string.IsNullOrWhiteSpace(best.BadgeText) ? best.BadgeText : (pct != null ? $"خصم {pct}%" : "خصم");
            return (bestFinal, badge, pct);
        }


        var variants = (productIds.Count == 0)
            ? new List<ProductVariant>()
            : await _db.ProductVariants.AsNoTracking()
                .Where(v => productIds.Contains(v.ProductId) && v.IsActive)
                .ToListAsync();
        var addons = (productIds.Count == 0)
            ? new List<ProductAddon>()
            : await _db.ProductAddons.AsNoTracking()
                .Where(a => productIds.Contains(a.ProductId) && a.IsActive)
                .ToListAsync();

        decimal subtotalAfter = 0;
        decimal subtotalBefore = 0;
        var orderItems = new List<OrderItem>();
        foreach (var it in req.Items)
        {
            // Offer item (negative ProductId)
            if (it.ProductId < 0)
            {
                var oid = Math.Abs(it.ProductId);
                var off = offers.First(x => x.Id == oid);
                decimal baseUnit = (off.PriceAfter ?? off.PriceBefore ?? 0);

                // If offer price is not set, compute a fallback from linked products (sum of product prices).
                if (baseUnit <= 0)
                {
                    var linked = offerProductLinks.Where(x => x.OfferId == oid).Select(x => x.ProductId).Distinct().ToList();
                    if (linked.Count > 0)
                    {
                        foreach (var pid in linked)
                        {
                            var pr = products.FirstOrDefault(p => p.Id == pid);
                            if (pr != null) baseUnit += pr.Price;
                        }
                    }
                }

                if (baseUnit <= 0) return BadRequest(new { error = "offer_price_missing", offerId = oid });

                // Optional: allow offer to behave like a product (variants/addons) if it is linked to a product.
                // We reuse the FIRST linked product as a "template" for options.
                int? templateProductId = offerPrimaryProduct.ContainsKey(oid) ? offerPrimaryProduct[oid] : null;

                // Parse options snapshot if present.
                // NOTE: Customer apps may send either offer* keys OR the generic product keys.
                // We accept both to keep printing/receipt details consistent.
                int? offerVariantId = null;
                List<int> offerAddonIds = new();
				// NOTE: we intentionally avoid the variable name 'note' here because later
				// in the same method we declare another 'note' for normal products. C# does
				// not allow such shadowing across sibling blocks (CS0136).
				string? offerItemNote = null;
                if (!string.IsNullOrWhiteSpace(it.OptionsSnapshot))
                {
                    try
                    {
                        using var doc = System.Text.Json.JsonDocument.Parse(it.OptionsSnapshot);
                        var root = doc.RootElement;
                        // Variant
                        if (root.TryGetProperty("offerVariantId", out var vEl) && vEl.ValueKind == System.Text.Json.JsonValueKind.Number)
                            offerVariantId = vEl.GetInt32();
                        else if (root.TryGetProperty("variantId", out var vEl2) && vEl2.ValueKind == System.Text.Json.JsonValueKind.Number)
                            offerVariantId = vEl2.GetInt32();

                        // Addons
                        if (root.TryGetProperty("offerAddonIds", out var aEl) && aEl.ValueKind == System.Text.Json.JsonValueKind.Array)
                        {
                            foreach (var x in aEl.EnumerateArray())
                                if (x.ValueKind == System.Text.Json.JsonValueKind.Number) offerAddonIds.Add(x.GetInt32());
                        }
                        else if (root.TryGetProperty("addonIds", out var aEl2) && aEl2.ValueKind == System.Text.Json.JsonValueKind.Array)
                        {
                            foreach (var x in aEl2.EnumerateArray())
                                if (x.ValueKind == System.Text.Json.JsonValueKind.Number) offerAddonIds.Add(x.GetInt32());
                        }

                        // Notes: we use the generic 'note' (per-cart-item notes). We intentionally do NOT keep offerNote.
							if (root.TryGetProperty("note", out var nEl) && nEl.ValueKind == System.Text.Json.JsonValueKind.String)
								offerItemNote = nEl.GetString();
							else if (root.TryGetProperty("offerNote", out var nEl2) && nEl2.ValueKind == System.Text.Json.JsonValueKind.String)
								offerItemNote = nEl2.GetString();
                    }
                    catch { }
                }

                decimal offerVariantDelta = 0;
                decimal offerAddonsSum = 0;
                if (templateProductId != null)
                {
                    if (offerVariantId != null)
                    {
                        var v = variants.FirstOrDefault(x => x.ProductId == templateProductId.Value && x.Id == offerVariantId.Value);
                        if (v != null) offerVariantDelta = v.PriceDelta;
                    }
                    foreach (var aid in offerAddonIds.Distinct())
                    {
                        var a = addons.FirstOrDefault(x => x.ProductId == templateProductId.Value && x.Id == aid);
                        if (a != null) offerAddonsSum += a.Price;
                    }
                }

                var unit = baseUnit + offerVariantDelta + offerAddonsSum;
                subtotalAfter += unit * it.Quantity;
                subtotalBefore += unit * it.Quantity;
                orderItems.Add(new OrderItem
                {
                    ProductId = -oid,
                    ProductNameSnapshot = off.Title,
                    UnitPriceSnapshot = unit,
                    Quantity = it.Quantity,
                    OptionsSnapshot = System.Text.Json.JsonSerializer.Serialize(new
                    {
                        type = "offer",
                        offerId = oid,
                        templateProductId,
                        offerVariantId,
                        offerAddonIds = offerAddonIds.Distinct().OrderBy(x => x).ToList(),
						// keep only the generic per-item note (if any)
						note = string.IsNullOrWhiteSpace(offerItemNote) ? null : offerItemNote
                    })
                });
                continue;
            }

            var p = products.First(x => x.Id == it.ProductId);

            // Resolve options (variant/addons) and compute correct unit price.
            int? variantId = null;
            List<int> addonIds = new();
            string? note = null;
            if (!string.IsNullOrWhiteSpace(it.OptionsSnapshot))
            {
                try
                {
                    using var doc = System.Text.Json.JsonDocument.Parse(it.OptionsSnapshot);
                    var root = doc.RootElement;
                    if (root.TryGetProperty("variantId", out var vEl) && vEl.ValueKind == System.Text.Json.JsonValueKind.Number)
                        variantId = vEl.GetInt32();
                    if (root.TryGetProperty("addonIds", out var aEl) && aEl.ValueKind == System.Text.Json.JsonValueKind.Array)
                    {
                        foreach (var x in aEl.EnumerateArray())
                            if (x.ValueKind == System.Text.Json.JsonValueKind.Number) addonIds.Add(x.GetInt32());
                    }
                    if (root.TryGetProperty("note", out var nEl) && nEl.ValueKind == System.Text.Json.JsonValueKind.String)
                        note = nEl.GetString();
                }
                catch
                {
                    // ignore malformed options snapshot
                }
            }

            decimal variantDelta = 0;
            string? variantName = null;
            if (variantId != null)
            {
                var v = variants.FirstOrDefault(x => x.ProductId == p.Id && x.Id == variantId.Value);
                if (v != null)
                {
                    variantDelta = v.PriceDelta;
                    variantName = v.Name;
                }
            }

            decimal addonsSum = 0;
            var addonSnapshots = new List<object>();
            foreach (var aid in addonIds.Distinct())
            {
                var a = addons.FirstOrDefault(x => x.ProductId == p.Id && x.Id == aid);
                if (a != null)
                {
                    addonsSum += a.Price;
                    addonSnapshots.Add(new { a.Id, a.Name, a.Price });
                }
            }

            // Automatic discounts:
            // - Product discount applies only to this product
            // - Category discount applies to all products in the category
            // - Best discount wins (lowest final base price)
            var baseOriginal = p.Price;
            var d = BestDiscountForProduct(p.Id, p.CategoryId, baseOriginal);
            var baseAfter = d.finalBasePrice;

            var unitPriceBefore = baseOriginal + variantDelta + addonsSum;
            var unitPriceAfter = baseAfter + variantDelta + addonsSum;

            subtotalBefore += unitPriceBefore * it.Quantity;
            subtotalAfter += unitPriceAfter * it.Quantity;

            orderItems.Add(new OrderItem
            {
                ProductId = p.Id,
                ProductNameSnapshot = p.Name,
                UnitPriceSnapshot = unitPriceAfter,
                Quantity = it.Quantity,
                OptionsSnapshot = System.Text.Json.JsonSerializer.Serialize(new
                {
                    variantId,
                    variantName,
                    variantDelta,
                    addons = addonSnapshots,
                    note,
                    discount = new
                    {
                        baseOriginal,
                        baseAfter,
                        percent = d.percent,
                        badge = d.badgeText
                    }
                })
            });
        }

        if (subtotalAfter < settings.MinOrderAmount)
            return BadRequest(new { error = "الطلب أقل من الحد الأدنى", minOrder = settings.MinOrderAmount });

        double deliveryDistanceKm = 0;
        decimal deliveryFee;
        if (isPickup)
        {
            deliveryFee = 0;
        }
        else
        {
            if (settings.RestaurantLat != 0 || settings.RestaurantLng != 0)
                deliveryDistanceKm = HaversineKm(settings.RestaurantLat, settings.RestaurantLng, finalLat, finalLng);
            // توصيل مجاني ضمن مسافة معيّنة إن تم تفعيل هذه الميزة
            if (settings.FreeDeliveryMaxKm > 0 && deliveryDistanceKm > 0 && deliveryDistanceKm <= settings.FreeDeliveryMaxKm)
                deliveryFee = 0;
            else if (settings.DeliveryFeePerKm > 0 && deliveryDistanceKm >= 0)
                deliveryFee = Math.Round((decimal)deliveryDistanceKm * settings.DeliveryFeePerKm, 2);
            else
                deliveryFee = settings.DeliveryFeeType == DeliveryFeeType.Fixed ? settings.DeliveryFeeValue : settings.DeliveryFeeValue;
        }

        var totalBeforeDiscount = subtotalBefore + deliveryFee;
        var cartDiscount = subtotalBefore - subtotalAfter;
        if (cartDiscount < 0) cartDiscount = 0;
        var total = (subtotalAfter + deliveryFee);

        // Update last location for delivery orders only (not for pickup).
        if (!isPickup)
        {
            customer.LastLat = finalLat;
            customer.LastLng = finalLng;
        }

        var order = new Order
        {
            CustomerId = customer.Id,
            IdempotencyKey = key,
            CustomerAddressId = addr?.Id,
            DeliveryLat = finalLat,
            DeliveryLng = finalLng,
            DeliveryAddress = finalAddress,
            OrderType = isPickup ? "pickup" : "delivery",
            DeliveryDistanceKm = Math.Round(deliveryDistanceKm, 3),
            Notes = req.Notes,
            Subtotal = subtotalAfter,
            DeliveryFee = deliveryFee,
            TotalBeforeDiscount = totalBeforeDiscount,
            CartDiscount = cartDiscount,
            Total = total,
            OrderEditableUntilUtc = DateTime.UtcNow.AddMinutes(2),
            CurrentStatus = OrderStatus.New,
            Items = orderItems,
            StatusHistory = new List<OrderStatusHistory>
            {
                new()
                {
                    Status = OrderStatus.New,
                    Comment = "تم إنشاء الطلب",
                    ReasonCode = "created",
                    ChangedByType = "customer",
                    ChangedById = customer.Id
                }
            }
        };

        _db.Orders.Add(order);
        await _db.SaveChangesAsync();

        await _hub.Clients.Group("admin").SendAsync("order_new", new { order.Id, order.Total, order.CreatedAtUtc });
        await _hub.Clients.Group($"customer-{customer.Id}").SendAsync("order_status", new { orderId = order.Id, status = order.CurrentStatus });

        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Admin, null,
            "طلب جديد", $"طلب جديد رقم #{order.Id} بقيمة {order.Total:0.##}", order.Id);
        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Customer, customer.Id,
            "تم استلام طلبك", $"تم إنشاء طلبك رقم #{order.Id} بنجاح", order.Id);

        // Customer push (FCM) on create
        await _notifications.SendCustomerOrderStatusPushIfNeededAsync(customer.Id, order.Id, order.CurrentStatus, order.PrepEtaMinutes, order.DeliveryEtaMinutes);

        return Ok(new { id = order.Id });
    }

    [HttpGet("orders/{customerId:int}")]
    public async Task<IActionResult> ListOrders(int customerId)
    {
        // IMPORTANT:
        // MySQL "datetime" does not preserve DateTimeKind.
        // Even if we store UTC timestamps, EF may materialize them as Kind=Unspecified,
        // which makes Flutter/Dart parse them as LOCAL time (no trailing "Z"), causing
        // edit/cancel windows to appear expired immediately.
        // لذلك نقوم بتثبيت الـ Kind = UTC قبل الإرجاع ليتم تسلسلها على شكل ISO مع Z.

        var now = DateTime.UtcNow;

        var raw = await _db.Orders.AsNoTracking()
            .Where(o => o.CustomerId == customerId)
            .OrderByDescending(o => o.CreatedAtUtc)
            .ToListAsync();

        var orders = raw.Select(o =>
        {
            // Force Kind=UTC for all returned timestamps (MySQL datetime loses Kind)
            var createdUtc = DateTime.SpecifyKind(o.CreatedAtUtc, DateTimeKind.Utc);
            DateTime? editableUtc = o.OrderEditableUntilUtc.HasValue
                ? DateTime.SpecifyKind(o.OrderEditableUntilUtc.Value, DateTimeKind.Utc)
                : null;
            DateTime? expectedUtc = o.ExpectedDeliveryAtUtc.HasValue
                ? DateTime.SpecifyKind(o.ExpectedDeliveryAtUtc.Value, DateTimeKind.Utc)
                : null;
            DateTime? lastEtaUtc = o.LastEtaUpdatedAtUtc.HasValue
                ? DateTime.SpecifyKind(o.LastEtaUpdatedAtUtc.Value, DateTimeKind.Utc)
                : null;

            // Market rule: customer can cancel only within 2 minutes from creation.
            var canCancel = (now - createdUtc) <= TimeSpan.FromMinutes(2)
                            && o.CurrentStatus != OrderStatus.Delivered
                            && o.CurrentStatus != OrderStatus.Cancelled;

            return new
            {
                o.Id,
                o.CurrentStatus,
                o.Total,
                orderEditableUntilUtc = editableUtc,
                canEdit = (editableUtc != null && now <= editableUtc
                           && o.CurrentStatus != OrderStatus.Delivered && o.CurrentStatus != OrderStatus.Cancelled),
                canCancel,
                createdAtUtc = createdUtc,
                o.PrepEtaMinutes,
                o.DeliveryEtaMinutes,
                expectedDeliveryAtUtc = expectedUtc,
                lastEtaUpdatedAtUtc = lastEtaUtc
            };
        }).ToList();

        return Ok(orders);
    }

    [HttpGet("order/{orderId:int}")]
    public async Task<IActionResult> GetOrder(int orderId)
    {
        var o = await _db.Orders.AsNoTracking()
            .Include(x => x.Items)
            .Include(x => x.StatusHistory)
            .FirstOrDefaultAsync(x => x.Id == orderId);
        if (o == null) return NotFound(new { error = "not_found" });

        var rating = await _db.OrderRatings.AsNoTracking().FirstOrDefaultAsync(r => r.OrderId == o.Id);

        var createdUtc = DateTime.SpecifyKind(o.CreatedAtUtc, DateTimeKind.Utc);
        DateTime? editableUtc = o.OrderEditableUntilUtc.HasValue
            ? DateTime.SpecifyKind(o.OrderEditableUntilUtc.Value, DateTimeKind.Utc)
            : null;
        DateTime? expectedUtc = o.ExpectedDeliveryAtUtc.HasValue
            ? DateTime.SpecifyKind(o.ExpectedDeliveryAtUtc.Value, DateTimeKind.Utc)
            : null;
        DateTime? lastEtaUtc = o.LastEtaUpdatedAtUtc.HasValue
            ? DateTime.SpecifyKind(o.LastEtaUpdatedAtUtc.Value, DateTimeKind.Utc)
            : null;

        var canEdit = editableUtc != null && DateTime.UtcNow <= editableUtc && o.CurrentStatus != OrderStatus.Delivered && o.CurrentStatus != OrderStatus.Cancelled;
        // Market rule: customer can cancel only within 2 minutes from creation.
        var canCancel = (DateTime.UtcNow - createdUtc) <= TimeSpan.FromMinutes(2)
                        && o.CurrentStatus != OrderStatus.Delivered
                        && o.CurrentStatus != OrderStatus.Cancelled;

        // Edited flag should be true ONLY when the customer actually edited the order,
        // not when the customer simply created it.
        var editedByCustomer = o.StatusHistory != null && o.StatusHistory.Any(h =>
            (h.ReasonCode ?? "") == "customer_edit" ||
            ((h.Comment ?? "").Contains("تم تعديل الطلب")));
        return Ok(new
        {
            o.Id,
            o.CustomerId,
            o.DriverId,
            o.CurrentStatus,
            o.Subtotal,
            o.DeliveryFee,
            o.Total,
            createdAtUtc = createdUtc,
            orderEditableUntilUtc = editableUtc,
            canEdit,
            canCancel,
            editedByCustomer,
            o.DeliveryLat,
            o.DeliveryLng,
            o.DeliveryAddress,
            o.Notes,
            o.PrepEtaMinutes,
            o.DeliveryEtaMinutes,
            expectedDeliveryAtUtc = expectedUtc,
            lastEtaUpdatedAtUtc = lastEtaUtc,
            orderRating = rating == null ? null : new { rating.OrderId, restaurantRate = rating.RestaurantRate, driverRate = rating.DriverRate, rating.Comment, createdAtUtc = DateTime.SpecifyKind(rating.CreatedAtUtc, DateTimeKind.Utc) },
            items = o.Items.Select(i => new { i.ProductId, i.ProductNameSnapshot, i.UnitPriceSnapshot, i.Quantity, i.OptionsSnapshot }),
            history = o.StatusHistory.OrderBy(h => h.ChangedAtUtc).Select(h => new { h.Status, changedAtUtc = DateTime.SpecifyKind(h.ChangedAtUtc, DateTimeKind.Utc), h.Comment })
        });
    }

    

    public record EditOrderRequest(
        int CustomerId,
        List<OrderItemReq> Items,
        string? Notes,
        double? DeliveryLat,
        double? DeliveryLng,
        string? DeliveryAddress
    );

    [HttpPost("order/{orderId:int}/edit")]
    public async Task<IActionResult> EditOrder(int orderId, EditOrderRequest req)
    {
        var o = await _db.Orders
            .Include(x => x.Items)
            .FirstOrDefaultAsync(x => x.Id == orderId);
        if (o == null) return NotFound(new { error = "not_found" });
        if (o.CustomerId != req.CustomerId) return Forbid();

        // NOTE: MySQL datetime may return Kind=Unspecified; force UTC before comparing.
        var editableUntilUtc = o.OrderEditableUntilUtc.HasValue
            ? DateTime.SpecifyKind(o.OrderEditableUntilUtc.Value, DateTimeKind.Utc)
            : (DateTime?)null;

        if (editableUntilUtc == null || DateTime.UtcNow > editableUntilUtc)
            return BadRequest(new { error = "edit_window_closed", message = "انتهت مدة التعديل" });

        if (o.CurrentStatus == OrderStatus.Delivered || o.CurrentStatus == OrderStatus.Cancelled)
            return BadRequest(new { error = "not_editable", message = "لا يمكن تعديل هذا الطلب" });

        if (req.Items == null || req.Items.Count == 0)
            return BadRequest(new { error = "empty_items", message = "لا يمكن أن يكون الطلب فارغاً" });

        // Items may contain:
        // - Product items: ProductId > 0
        // - Offer items: ProductId < 0 (negative offerId)
        var productIds = req.Items.Where(i => i.ProductId > 0).Select(i => i.ProductId).Distinct().ToList();
        var offerIds = req.Items.Where(i => i.ProductId < 0).Select(i => Math.Abs(i.ProductId)).Distinct().ToList();

        // Offers may be linked to products so we can reuse variants/addons ("عرض مثل المنيو").
        var offerProductLinks = (offerIds.Count == 0)
            ? new List<OfferProduct>()
            : await _db.OfferProducts.AsNoTracking().Where(x => offerIds.Contains(x.OfferId)).ToListAsync();
        var offerPrimaryProduct = offerProductLinks
            .GroupBy(x => x.OfferId)
            .ToDictionary(g => g.Key, g => g.Select(x => x.ProductId).FirstOrDefault());

        var linkedProductIds = offerProductLinks.Select(x => x.ProductId).Distinct().ToList();
        foreach (var pid in linkedProductIds)
            if (!productIds.Contains(pid)) productIds.Add(pid);

        var products = (productIds.Count == 0)
            ? new List<Product>()
            : await _db.Products.Where(p => productIds.Contains(p.Id) && p.IsActive).ToListAsync();
        if (products.Count != productIds.Count)
            return BadRequest(new { error = "invalid_items", message = "بعض الأصناف غير صحيحة" });

        var offers = (offerIds.Count == 0)
            ? new List<Offer>()
            : await _db.Offers.AsNoTracking().Where(o2 => offerIds.Contains(o2.Id) && o2.IsActive).ToListAsync();
        if (offers.Count != offerIds.Count)
            return BadRequest(new { error = "invalid_items", message = "بعض العروض غير صحيحة" });

        var variants = (productIds.Count == 0)
            ? new List<ProductVariant>()
            : await _db.ProductVariants.AsNoTracking()
                .Where(v => productIds.Contains(v.ProductId) && v.IsActive)
                .ToListAsync();
        var addons = (productIds.Count == 0)
            ? new List<ProductAddon>()
            : await _db.ProductAddons.AsNoTracking()
                .Where(a => productIds.Contains(a.ProductId) && a.IsActive)
                .ToListAsync();

        // Active discounts (market-style) - applied automatically (no coupon codes)
        var now = DateTime.UtcNow;
        var discounts = await _db.Discounts.AsNoTracking()
            .Where(d => d.IsActive
                        && d.TargetType != DiscountTargetType.Cart
                        && (d.StartsAtUtc == null || d.StartsAtUtc <= now)
                        && (d.EndsAtUtc == null || d.EndsAtUtc >= now))
            .ToListAsync();

        decimal ApplyDiscount(decimal original, Discount d)
        {
            if (original <= 0) return 0;
            decimal v = original;
            if (d.ValueType == DiscountValueType.Percent)
            {
                var p = d.Percent ?? 0;
                v = original - (original * p / 100m);
            }
            else
            {
                var a = d.Amount ?? 0;
                v = original - a;
            }
            if (v < 0) v = 0;
            return Math.Round(v, 2);
        }

        (decimal finalBasePrice, string? badgeText, decimal? percent) BestDiscountForProduct(int productId, int categoryId, decimal original)
        {
            if (discounts.Count == 0) return (original, null, null);
            var prod = discounts.Where(x => x.TargetType == DiscountTargetType.Product && x.TargetId == productId).ToList();
            var cat = discounts.Where(x => x.TargetType == DiscountTargetType.Category && x.TargetId == categoryId).ToList();
            Discount? best = null;
            decimal bestFinal = original;
            foreach (var d in prod.Concat(cat))
            {
                var f = ApplyDiscount(original, d);
                if (f < bestFinal)
                {
                    bestFinal = f;
                    best = d;
                }
            }
            if (best == null || bestFinal >= original) return (original, null, null);
            decimal? pct = null;
            if (best.ValueType == DiscountValueType.Percent) pct = best.Percent;
            else if (original > 0) pct = Math.Round((1m - (bestFinal / original)) * 100m, 0);
            var badge = !string.IsNullOrWhiteSpace(best.BadgeText) ? best.BadgeText : (pct != null ? $"خصم {pct}%" : "خصم");
            return (bestFinal, badge, pct);
        }

        decimal subtotalAfter = 0;
        decimal subtotalBefore = 0;
        var newItems = new List<OrderItem>();
        foreach (var it in req.Items)
        {
            // Offer item (negative ProductId) - keep behavior consistent with CreateOrder.
            if (it.ProductId < 0)
            {
                var oid = Math.Abs(it.ProductId);
                var off = offers.First(x => x.Id == oid);

                decimal baseUnit = (off.PriceAfter ?? off.PriceBefore ?? 0);
                if (baseUnit <= 0)
                {
                    var linked = offerProductLinks.Where(x => x.OfferId == oid).Select(x => x.ProductId).Distinct().ToList();
                    if (linked.Count > 0)
                    {
                        foreach (var pid in linked)
                        {
                            var pr = products.FirstOrDefault(p2 => p2.Id == pid);
                            if (pr != null) baseUnit += pr.Price;
                        }
                    }
                }
                if (baseUnit <= 0)
                    return BadRequest(new { error = "offer_price_missing", offerId = oid, message = "سعر العرض غير متوفر" });

                int? templateProductId = offerPrimaryProduct.ContainsKey(oid) ? offerPrimaryProduct[oid] : null;

                // Parse options snapshot. Accept both offer* keys and generic keys for compatibility.
                int? offerVariantId = null;
                List<int> offerAddonIds = new();
                // NOTE: keep only the generic per-item note (the cart item note). We intentionally avoid
                // the variable name 'note' here because later in the same method another 'note' variable
                // exists for normal products and C# would reject shadowing (CS0136).
                string? offerItemNote = null;
                if (!string.IsNullOrWhiteSpace(it.OptionsSnapshot))
                {
                    try
                    {
                        using var doc = System.Text.Json.JsonDocument.Parse(it.OptionsSnapshot);
                        var root = doc.RootElement;

                        // Variant
                        if (root.TryGetProperty("offerVariantId", out var vEl) && vEl.ValueKind == System.Text.Json.JsonValueKind.Number)
                            offerVariantId = vEl.GetInt32();
                        else if (root.TryGetProperty("variantId", out var vEl2) && vEl2.ValueKind == System.Text.Json.JsonValueKind.Number)
                            offerVariantId = vEl2.GetInt32();

                        // Addons
                        if (root.TryGetProperty("offerAddonIds", out var aEl) && aEl.ValueKind == System.Text.Json.JsonValueKind.Array)
                        {
                            foreach (var x in aEl.EnumerateArray())
                                if (x.ValueKind == System.Text.Json.JsonValueKind.Number) offerAddonIds.Add(x.GetInt32());
                        }
                        else if (root.TryGetProperty("addonIds", out var aEl2) && aEl2.ValueKind == System.Text.Json.JsonValueKind.Array)
                        {
                            foreach (var x in aEl2.EnumerateArray())
                                if (x.ValueKind == System.Text.Json.JsonValueKind.Number) offerAddonIds.Add(x.GetInt32());
                        }

                        // Note (generic per-item note)
							if (root.TryGetProperty("note", out var nEl) && nEl.ValueKind == System.Text.Json.JsonValueKind.String)
								offerItemNote = nEl.GetString();
							else if (root.TryGetProperty("offerNote", out var nEl2) && nEl2.ValueKind == System.Text.Json.JsonValueKind.String)
								offerItemNote = nEl2.GetString();
                    }
                    catch { }
                }

                decimal offerVariantDelta = 0;
                decimal offerAddonsSum = 0;
                if (templateProductId != null)
                {
                    if (offerVariantId != null)
                    {
                        var v = variants.FirstOrDefault(x => x.ProductId == templateProductId.Value && x.Id == offerVariantId.Value);
                        if (v != null) offerVariantDelta = v.PriceDelta;
                    }
                    foreach (var aid in offerAddonIds.Distinct())
                    {
                        var a = addons.FirstOrDefault(x => x.ProductId == templateProductId.Value && x.Id == aid);
                        if (a != null) offerAddonsSum += a.Price;
                    }
                }

                var unit = baseUnit + offerVariantDelta + offerAddonsSum;
                if (it.Quantity < 1)
                    return BadRequest(new { error = "invalid_qty", message = "الكمية غير صحيحة" });

                subtotalBefore += unit * it.Quantity;
                subtotalAfter += unit * it.Quantity;

                newItems.Add(new OrderItem
                {
                    OrderId = o.Id,
                    ProductId = -oid,
                    ProductNameSnapshot = off.Title,
                    UnitPriceSnapshot = unit,
                    Quantity = it.Quantity,
                    OptionsSnapshot = System.Text.Json.JsonSerializer.Serialize(new
                    {
                        type = "offer",
                        offerId = oid,
                        templateProductId,
                        offerVariantId,
                        offerAddonIds = offerAddonIds.Distinct().OrderBy(x => x).ToList(),
						// keep only the generic per-item note (if any)
						note = string.IsNullOrWhiteSpace(offerItemNote) ? null : offerItemNote
                    })
                });
                continue;
            }

            var p = products.First(x => x.Id == it.ProductId);

            int? variantId = null;
            List<int> addonIds = new();
            if (!string.IsNullOrWhiteSpace(it.OptionsSnapshot))
            {
                try
                {
                    using var doc = System.Text.Json.JsonDocument.Parse(it.OptionsSnapshot);
                    var root = doc.RootElement;
                    if (root.TryGetProperty("variantId", out var vEl) && vEl.ValueKind == System.Text.Json.JsonValueKind.Number)
                        variantId = vEl.GetInt32();
                    if (root.TryGetProperty("addonIds", out var aEl) && aEl.ValueKind == System.Text.Json.JsonValueKind.Array)
                    {
                        foreach (var x in aEl.EnumerateArray())
                            if (x.ValueKind == System.Text.Json.JsonValueKind.Number) addonIds.Add(x.GetInt32());
                    }
                }
                catch { }
            }

	            decimal variantDelta = 0;
            string? variantName = null;
            if (variantId != null)
            {
                var v = variants.FirstOrDefault(x => x.ProductId == p.Id && x.Id == variantId.Value);
                if (v != null)
                {
                    variantName = v.Name;
	                    // PriceDelta is already decimal in DB
	                    variantDelta = v.PriceDelta;
                }
            }

            decimal addonsTotal = 0;
            if (addonIds.Count > 0)
            {
                foreach (var aid in addonIds)
                {
                    var a = addons.FirstOrDefault(x => x.ProductId == p.Id && x.Id == aid);
                    if (a != null)
                    {
	                        // Price is already decimal in DB
	                        addonsTotal += a.Price;
                    }
                }
            }

            var baseOriginal = p.Price;
            var d = BestDiscountForProduct(p.Id, p.CategoryId, baseOriginal);
            var baseAfter = d.finalBasePrice;

            var unitBefore = baseOriginal + variantDelta + addonsTotal;
            var unitAfter = baseAfter + variantDelta + addonsTotal;
            if (it.Quantity < 1) return BadRequest(new { error = "invalid_qty", message = "الكمية غير صحيحة" });

            subtotalBefore += unitBefore * it.Quantity;
            subtotalAfter += unitAfter * it.Quantity;

            newItems.Add(new OrderItem
            {
                OrderId = o.Id,
                ProductId = p.Id,
                ProductNameSnapshot = p.Name,
                UnitPriceSnapshot = unitAfter,
                Quantity = it.Quantity,
                OptionsSnapshot = System.Text.Json.JsonSerializer.Serialize(new
                {
                    variantId,
                    variantName,
                    variantDelta,
                    addonIds,
                    discount = new
                    {
                        baseOriginal,
                        baseAfter,
                        percent = d.percent,
                        badge = d.badgeText
                    }
                })
            });
        }

        // Allow customer to edit delivery location (within edit window) without creating a new order.
        if (req.DeliveryLat != null && req.DeliveryLng != null)
        {
            var lat = req.DeliveryLat.Value;
            var lng = req.DeliveryLng.Value;
            if (lat < -90 || lat > 90 || lng < -180 || lng > 180)
                return BadRequest(new { error = "invalid_location", message = "الموقع غير صحيح" });

            o.DeliveryLat = lat;
            o.DeliveryLng = lng;
            o.OrderType = "delivery";
            if (!string.IsNullOrWhiteSpace(req.DeliveryAddress))
                o.DeliveryAddress = req.DeliveryAddress.Trim();
        }
        else if (!string.IsNullOrWhiteSpace(req.DeliveryAddress))
        {
            // If only the text address changed (rare), still keep it.
            o.DeliveryAddress = req.DeliveryAddress.Trim();
        }

        // Keep same delivery fee type for edits (no recalculation based on location)
        var settings = await _db.RestaurantSettings.AsNoTracking().FirstOrDefaultAsync();
        decimal deliveryFee = o.DeliveryFee;
        if (settings != null)
        {
            if (settings.DeliveryFeeType == DeliveryFeeType.Fixed)
                deliveryFee = settings.DeliveryFeeValue;
        }

        o.Notes = string.IsNullOrWhiteSpace(req.Notes) ? null : req.Notes.Trim();
        o.Subtotal = subtotalAfter;
        o.DeliveryFee = deliveryFee;
        o.TotalBeforeDiscount = subtotalBefore + deliveryFee;
        o.CartDiscount = Math.Max(0, subtotalBefore - subtotalAfter);
        o.Total = subtotalAfter + deliveryFee;

        // Add a lightweight history entry to show that the customer edited the order.
        o.StatusHistory.Add(new OrderStatusHistory
        {
            OrderId = o.Id,
            Status = o.CurrentStatus,
            ChangedAtUtc = DateTime.UtcNow,
            ChangedByType = "customer",
            ChangedById = o.CustomerId,
            ReasonCode = "customer_edit",
            Comment = "تم تعديل الطلب من قبل الزبون"
        });

        // Replace items
        _db.OrderItems.RemoveRange(o.Items);
        await _db.SaveChangesAsync(); // ensure delete first for SQLite FK
        _db.OrderItems.AddRange(newItems);
        await _db.SaveChangesAsync();

        // Notify admins (real-time + FCM topic) that customer edited the order
        var custName = await _db.Customers.AsNoTracking()
            .Where(c => c.Id == o.CustomerId)
            .Select(c => c.Name)
            .FirstOrDefaultAsync();
        custName = string.IsNullOrWhiteSpace(custName) ? $"#{o.CustomerId}" : custName.Trim();

        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Admin, null,
            "تم تعديل الطلب",
            $"قام {custName} بتعديل الطلب رقم #{o.Id}",
            relatedOrderId: o.Id);

        await _hub.Clients.Group("admin").SendAsync("order_edited", new { orderId = o.Id, customerName = custName, o.Subtotal, o.DeliveryFee, o.Total });
        await _hub.Clients.Group($"customer-{o.CustomerId}").SendAsync("order_edited", new { orderId = o.Id });

        return Ok(new { ok = true, orderId = o.Id, editableUntilUtc = o.OrderEditableUntilUtc, o.Subtotal, o.DeliveryFee, o.Total });
    }

// Returns the last delivered order that still needs rating.
    [HttpGet("pending-rating/{customerId:int}")]
    public async Task<IActionResult> PendingRating(int customerId)
    {
        var lastDelivered = await _db.Orders.AsNoTracking()
            .Where(o => o.CustomerId == customerId && o.DeliveredAtUtc != null)
            .OrderByDescending(o => o.DeliveredAtUtc)
            .Select(o => new { o.Id, o.DeliveredAtUtc, o.DriverId })
            .FirstOrDefaultAsync();

        if (lastDelivered == null) return Ok(new { hasPending = false });

        var r2 = await _db.OrderRatings.AsNoTracking().FirstOrDefaultAsync(x => x.OrderId == lastDelivered.Id);
        var restaurantOk = r2 != null && r2.RestaurantRate >= 1 && r2.RestaurantRate <= 5;
        var driverOk = lastDelivered.DriverId == null || (r2 != null && r2.DriverRate >= 1 && r2.DriverRate <= 5);
        if (restaurantOk && driverOk) return Ok(new { hasPending = false });

        return Ok(new { hasPending = true, orderId = lastDelivered.Id, hasDriver = lastDelivered.DriverId != null });
    }

    // Customer cancellation request.
    // NOTE: we accept both `reason` (free text) and legacy `reasonCode` (older clients).
    public record CancelOrderReq(int CustomerId, string? Reason = null, string? ReasonCode = null);

    private static readonly Dictionary<string, string> CancelReasonLabelsLegacy = new()
    {
        ["changed_mind"] = "غيرت رأيي",
        ["wrong_items"] = "طلبت أصناف بالخطأ",
        ["wrong_address"] = "العنوان غير صحيح",
        ["too_expensive"] = "السعر مرتفع",
        ["other"] = "سبب آخر"
    };

    
[HttpPost("order/{orderId:int}/cancel")]
	    public async Task<IActionResult> CancelOrder(int orderId, CancelOrderReq req)
    {
        var o = await _db.Orders
            .Include(x => x.StatusHistory)
            .FirstOrDefaultAsync(x => x.Id == orderId);
        if (o == null) return NotFound(new { error = "not_found" });
        if (o.CustomerId != req.CustomerId) return Forbid();

        if (o.CurrentStatus == OrderStatus.Delivered || o.CurrentStatus == OrderStatus.Cancelled)
            return BadRequest(new { error = "cannot_cancel", message = "لا يمكن إلغاء هذا الطلب" });

        // Only within 2 minutes from creation.
        // NOTE: MySQL datetime may return Kind=Unspecified; force UTC before comparing.
        var createdUtc = DateTime.SpecifyKind(o.CreatedAtUtc, DateTimeKind.Utc);
        if ((DateTime.UtcNow - createdUtc) > TimeSpan.FromMinutes(2))
            return BadRequest(new { error = "cancel_window_closed", message = "لم يعد بإمكانك إلغاء الطلب. راجع الإدارة في قسم الدردشة أو اتصال." });

        // Reason is required (market behavior): free-text written by customer.
        // For backward compatibility with older clients, we fall back to mapping ReasonCode.
        var reason = (req.Reason ?? "").Trim();
        if (string.IsNullOrWhiteSpace(reason))
        {
            var legacy = (req.ReasonCode ?? "").Trim();
            reason = CancelReasonLabelsLegacy.TryGetValue(legacy, out var l) ? l : "";
        }
        if (string.IsNullOrWhiteSpace(reason))
            return BadRequest(new { error = "reason_required", message = "يرجى كتابة سبب الإلغاء" });

        // Store a short snapshot of the reason on the order row (used by some list UIs).
        // (This is a TEXT column; we keep it short to avoid bloating list payloads.)
        o.CurrentStatus = OrderStatus.Cancelled;
        o.CancelReasonCode = reason.Length <= 80 ? reason : reason[..80];

        var reasonForHistory = reason.Length <= 200 ? reason : reason[..200];
        _db.OrderStatusHistory.Add(new OrderStatusHistory
        {
            OrderId = o.Id,
            Status = OrderStatus.Cancelled,
            ReasonCode = "customer_cancel",
            Comment = $"ملغي من قبل الزبون — {reasonForHistory}",
            ChangedByType = "customer",
            ChangedById = req.CustomerId,
            ChangedAtUtc = DateTime.UtcNow
        });

        // If a driver was assigned, free them.
        if (o.DriverId.HasValue)
        {
            var d = await _db.Drivers.FindAsync(o.DriverId.Value);
            if (d != null) d.Status = DriverStatus.Available;
        }

        await _db.SaveChangesAsync();

        // Realtime + notifications
        // Reuse the injected NotifyHub context (_hub). This avoids an undefined _hub field.
        await _hub.Clients.Group("admin").SendAsync("order_status", new { orderId = o.Id, status = o.CurrentStatus, driverId = o.DriverId });
        await _hub.Clients.Group($"customer-{o.CustomerId}").SendAsync("order_status", new { orderId = o.Id, status = o.CurrentStatus, driverId = o.DriverId });

        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Admin, null,
            "إلغاء من الزبون", $"الزبون ألغى الطلب #{o.Id} — {reasonForHistory}", o.Id);

        return Ok(new { ok = true });
    }


    public record RateDriverReq(int CustomerId, int Stars, string? Comment);

    [HttpPost("order/{orderId:int}/rate-driver")]
    public async Task<IActionResult> RateDriver(int orderId, RateDriverReq req)
    {
        if (req.Stars < 1 || req.Stars > 5)
            return BadRequest(new { error = "invalid_stars", message = "التقييم يجب أن يكون بين 1 و 5" });

        var o = await _db.Orders.FirstOrDefaultAsync(x => x.Id == orderId);
        if (o == null) return NotFound(new { error = "not_found" });
        if (o.CustomerId != req.CustomerId)
            return Forbid();
        if (o.CurrentStatus != OrderStatus.Delivered)
            return BadRequest(new { error = "not_delivered", message = "يمكن التقييم بعد تسليم الطلب فقط" });
        if (o.DriverId == null)
            return BadRequest(new { error = "no_driver", message = "لا يوجد سائق لهذا الطلب" });

        // Unified rating model (OrderRatings): Food + Driver in one row.
        // If restaurant rate not set yet, keep it as 5 by default until the customer submits it.
        var or = await _db.OrderRatings.FirstOrDefaultAsync(x => x.OrderId == o.Id);
        if (or == null)
        {
            or = new OrderRating
            {
                OrderId = o.Id,
                RestaurantRate = 5,
                DriverRate = req.Stars,
                Comment = string.IsNullOrWhiteSpace(req.Comment) ? null : req.Comment.Trim(),
                CreatedAtUtc = DateTime.UtcNow
            };
            _db.OrderRatings.Add(or);
        }
        else
        {
            or.DriverRate = req.Stars;
            if (!string.IsNullOrWhiteSpace(req.Comment))
                or.Comment = req.Comment.Trim();
        }
        await _db.SaveChangesAsync();

        await _hub.Clients.Group("admin").SendAsync("rating_added", new { orderId = o.Id, restaurantRate = or.RestaurantRate, driverRate = or.DriverRate, or.CreatedAtUtc });
        await _hub.Clients.All.SendAsync("ratings_updated");

        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Admin, null,
            "تقييم جديد", $"تم إضافة/تحديث تقييم الطلب #{o.Id}", o.Id);
        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Customer, o.CustomerId,
            "شكراً لتقييمك", "تم حفظ تقييمك بنجاح", o.Id);

        return Ok(new { ok = true, rating = new { orderId = or.OrderId, restaurantRate = or.RestaurantRate, driverRate = or.DriverRate, or.Comment, or.CreatedAtUtc } });
    }

    public record RateRestaurantReq(int CustomerId, int Stars, string? Comment);

    [HttpPost("order/{orderId:int}/rate-restaurant")]
    public async Task<IActionResult> RateRestaurant(int orderId, RateRestaurantReq req)
    {
        if (req.Stars < 1 || req.Stars > 5)
            return BadRequest(new { error = "invalid_stars", message = "التقييم يجب أن يكون بين 1 و 5" });

        var o = await _db.Orders.FirstOrDefaultAsync(x => x.Id == orderId);
        if (o == null) return NotFound(new { error = "not_found" });
        if (o.CustomerId != req.CustomerId)
            return Forbid();
        if (o.CurrentStatus != OrderStatus.Delivered)
            return BadRequest(new { error = "not_delivered", message = "يمكن التقييم بعد تسليم الطلب فقط" });

        // Unified rating model (OrderRatings): Food + Driver in one row.
        // If driver rate not set yet, keep it as 5 by default until the customer submits it.
        var or = await _db.OrderRatings.FirstOrDefaultAsync(x => x.OrderId == o.Id);
        if (or == null)
        {
            or = new OrderRating
            {
                OrderId = o.Id,
                RestaurantRate = req.Stars,
                DriverRate = 5,
                Comment = string.IsNullOrWhiteSpace(req.Comment) ? null : req.Comment.Trim(),
                CreatedAtUtc = DateTime.UtcNow
            };
            _db.OrderRatings.Add(or);
        }
        else
        {
            or.RestaurantRate = req.Stars;
            if (!string.IsNullOrWhiteSpace(req.Comment))
                or.Comment = req.Comment.Trim();
        }

        await _db.SaveChangesAsync();

        await _hub.Clients.Group("admin").SendAsync("rating_added", new { orderId = o.Id, restaurantRate = or.RestaurantRate, driverRate = or.DriverRate, or.CreatedAtUtc });
        await _hub.Clients.All.SendAsync("ratings_updated");

        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Admin, null,
            "تقييم جديد", $"تم إضافة/تحديث تقييم الطلب #{o.Id}", o.Id);
        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Customer, o.CustomerId,
            "شكراً لتقييمك", "تم حفظ تقييمك بنجاح", o.Id);

        return Ok(new { ok = true, rating = new { orderId = or.OrderId, restaurantRate = or.RestaurantRate, driverRate = or.DriverRate, or.Comment, or.CreatedAtUtc } });
    }

    public record CreateThreadReq(int CustomerId, int? OrderId, string Title, string Message);

    // Chat: معلومات عن آخر محادثة للزبون بدون إنشاء محادثة جديدة تلقائياً.
    [HttpGet("chat-thread/{customerId:int}")]
    public async Task<IActionResult> GetChatThreadInfo(int customerId)
    {
        var customer = await _db.Customers.FirstOrDefaultAsync(c => c.Id == customerId);
        if (customer == null) return NotFound(new { error = "not_found" });

        var thread = await _db.ComplaintThreads
            .OrderByDescending(t => t.UpdatedAtUtc)
            .FirstOrDefaultAsync(t => t.CustomerId == customerId);

        if (thread == null)
            return Ok(new { threadId = (int?)null, hasThread = false, customerId, isChatBlocked = customer.IsChatBlocked });

        return Ok(new { threadId = thread.Id, hasThread = true, customerId, isChatBlocked = customer.IsChatBlocked });
    }

    [HttpPost("complaints")]
    public async Task<IActionResult> CreateComplaint(CreateThreadReq req)
    {
        var customer = await _db.Customers.AsNoTracking().FirstOrDefaultAsync(c => c.Id == req.CustomerId);
        if (customer == null) return NotFound(new { error = "not_found" });
        if (customer.IsChatBlocked)
            return StatusCode(403, new { error = "chat_blocked", message = "تم إيقاف الدردشة من قبل الإدارة" });

        // Market requirement: ONE conversation per customer ("دردشة مع المطعم").
        // The customer can open the chat anytime; we either reuse the existing thread or create it.
        var now = DateTime.UtcNow;
        var cleanMsg = (req.Message ?? "").Trim();
        if (string.IsNullOrWhiteSpace(cleanMsg))
            return BadRequest(new { error = "empty_message", message = "الرسالة فارغة" });

        var thread = await _db.ComplaintThreads
            .OrderByDescending(t => t.UpdatedAtUtc)
            .FirstOrDefaultAsync(t => t.CustomerId == req.CustomerId);

        var isNew = false;
        if (thread == null)
        {
            isNew = true;
            thread = new ComplaintThread
            {
                CustomerId = req.CustomerId,
                OrderId = req.OrderId,
                Title = "دردشة مع المطعم",
                UpdatedAtUtc = now,
                LastCustomerSeenAtUtc = now
            };
            _db.ComplaintThreads.Add(thread);
            await _db.SaveChangesAsync();
        }

        // Always append as a message.
        var msg = new ComplaintMessage { ThreadId = thread.Id, FromAdmin = false, Message = cleanMsg };
        _db.ComplaintMessages.Add(msg);
        thread.UpdatedAtUtc = now;
        thread.LastCustomerSeenAtUtc = now;
        if (thread.OrderId == null && req.OrderId != null) thread.OrderId = req.OrderId;
        await _db.SaveChangesAsync();

        if (isNew)
        {
            await _hub.Clients.Group("admin").SendAsync("complaint_new", new { thread.Id, thread.Title, thread.CustomerId, thread.OrderId });
        }

        // Unified event name (real chat). Send to both admin + the customer so the sender gets
        // a single source of truth for UI updates (and can de-dup by message id).
        var payload = new { id = msg.Id, threadId = thread.Id, fromAdmin = false, message = cleanMsg, createdAtUtc = msg.CreatedAtUtc };
        await _hub.Clients.Group("admin").SendAsync("chat_message_received", payload);
        await _hub.Clients.Group($"customer-{thread.CustomerId}").SendAsync("chat_message_received", payload);

        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Admin, null,
            "رسالة جديدة", "رسالة جديدة من زبون", thread.OrderId);
        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Customer, thread.CustomerId,
            "تم إرسال رسالتك", "تم استلام رسالتك وسنقوم بالرد بأقرب وقت", thread.OrderId);
        return Ok(new { threadId = thread.Id, messageId = msg.Id, createdAtUtc = msg.CreatedAtUtc });
    }

    [HttpGet("complaints/{customerId:int}")]
    public async Task<IActionResult> ListComplaintThreads(int customerId)
    {
        var threads = await _db.ComplaintThreads.AsNoTracking()
            .Where(t => t.CustomerId == customerId)
            .Select(t => new
            {
                t.Id,
                t.Title,
                t.OrderId,
                t.CreatedAtUtc,
                t.UpdatedAtUtc,
                t.LastCustomerSeenAtUtc,
                lastMsg = _db.ComplaintMessages
                    .Where(m => m.ThreadId == t.Id)
                    .OrderByDescending(m => m.CreatedAtUtc)
                    .Select(m => new { m.FromAdmin, m.Message, m.CreatedAtUtc })
                    .FirstOrDefault(),
                unreadCount = _db.ComplaintMessages
                    .Where(m => m.ThreadId == t.Id && m.FromAdmin && (t.LastCustomerSeenAtUtc == null || m.CreatedAtUtc > t.LastCustomerSeenAtUtc))
                    .Count()
            })
            .OrderByDescending(x => x.lastMsg != null ? x.lastMsg.CreatedAtUtc : x.UpdatedAtUtc)
            .ToListAsync();

        var list = threads.Select(x => new
        {
            x.Id,
            x.Title,
            x.OrderId,
            x.CreatedAtUtc,
            x.UpdatedAtUtc,
            unreadCount = x.unreadCount,
            lastMessagePreview = x.lastMsg == null ? "" : (x.lastMsg.FromAdmin ? "الإدارة: " : "أنت: ") + (x.lastMsg.Message.Length > 60 ? x.lastMsg.Message.Substring(0, 60) + "…" : x.lastMsg.Message),
            lastMessageAtUtc = x.lastMsg?.CreatedAtUtc
        }).ToList();

        return Ok(list);
    }

    [HttpGet("complaint/{threadId:int}")]
    public async Task<IActionResult> GetComplaint(int threadId)
    {
        var t = await _db.ComplaintThreads.Include(x => x.Messages).FirstOrDefaultAsync(x => x.Id == threadId);
        if (t == null) return NotFound(new { error = "not_found" });

        // mark as read for customer
        t.LastCustomerSeenAtUtc = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(new
        {
            t.Id,
            t.Title,
            t.OrderId,
            t.CustomerId,
            messages = t.Messages.OrderBy(m => m.CreatedAtUtc).Select(m => new { m.Id, fromAdmin = m.FromAdmin, message = m.Message, m.CreatedAtUtc })
        });
    }

    public record SendComplaintMessageReq(string Message); // FromAdmin ignored for customer endpoint

    [HttpPost("complaint/{threadId:int}/message")]
    public async Task<IActionResult> SendComplaintMessage(int threadId, SendComplaintMessageReq req)
    {
        var t = await _db.ComplaintThreads.FirstOrDefaultAsync(x => x.Id == threadId);
        if (t == null) return NotFound(new { error = "not_found" });

        var customer = await _db.Customers.AsNoTracking().FirstOrDefaultAsync(c => c.Id == t.CustomerId);
        if (customer == null) return NotFound(new { error = "not_found" });
        if (customer.IsChatBlocked)
            return StatusCode(403, new { error = "chat_blocked", message = "تم إيقاف الدردشة من قبل الإدارة" });

        // Customer endpoint: always FromAdmin=false
        var cleanMsg = (req.Message ?? "").Trim();
        if (string.IsNullOrWhiteSpace(cleanMsg))
            return BadRequest(new { error = "empty_message", message = "الرسالة فارغة" });

        var now = DateTime.UtcNow;
        var msg = new ComplaintMessage { ThreadId = t.Id, FromAdmin = false, Message = cleanMsg, CreatedAtUtc = now };
        _db.ComplaintMessages.Add(msg);
        t.UpdatedAtUtc = now;
        await _db.SaveChangesAsync();

        // Realtime: unified event name for real chat (avoid duplicate deliveries on legacy listeners)
        // Include DB id for robust de-duplication on clients (reconnect / retry scenarios)
        var payload = new { id = msg.Id, threadId = t.Id, fromAdmin = false, message = cleanMsg, createdAtUtc = msg.CreatedAtUtc };
        await _hub.Clients.Group("admin").SendAsync("chat_message_received", payload);
        await _hub.Clients.Group($"customer-{t.CustomerId}").SendAsync("chat_message_received", payload);

        // In-app notification
        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Admin, null,
            "رسالة جديدة", "لديك رسالة جديدة من زبون", t.OrderId);

        // Push notification to admins for every message
        await _notifications.SendAdminChatPushAsync(t.OrderId, t.CustomerId, cleanMsg);

        return Ok(new { ok = true });
    }
}
