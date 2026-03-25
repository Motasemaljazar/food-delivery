using AdminDashboard.Data;
using AdminDashboard.Entities;
using AdminDashboard.Hubs;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;

namespace AdminDashboard.Controllers;

[ApiController]
[Route("api/admin")]
[Authorize(Policy = "AdminOnly")]
public class AdminController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IHubContext<NotifyHub> _notifyHub;
    private readonly NotificationService _notifications;
    private readonly AdminDashboard.Services.FcmService _fcm;
    private readonly AdminDashboard.Services.FirebaseAdminService _firebase;

    public AdminController(AppDbContext db, IHubContext<NotifyHub> notifyHub, NotificationService notifications, AdminDashboard.Services.FcmService fcm, AdminDashboard.Services.FirebaseAdminService firebase)
    {
        _db = db;
        _notifyHub = notifyHub;
        _notifications = notifications;
        _fcm = fcm;
        _firebase = firebase;
    }

    [HttpGet("drivers")]
    public async Task<IActionResult> ListDrivers()
    {
        var list = await _db.Drivers.AsNoTracking().OrderBy(d => d.Id).ToListAsync();
        return Ok(list);
    }

    [HttpGet("drivers/{id:int}/track")]
    public async Task<IActionResult> GetDriverTrack(int id, [FromQuery] int limit = 300)
    {
        limit = Math.Clamp(limit, 10, 1000);
        var points = await _db.DriverTrackPoints.AsNoTracking()
            .Where(p => p.DriverId == id)
            .OrderByDescending(p => p.CreatedAtUtc)
            .Take(limit)
            .OrderBy(p => p.CreatedAtUtc)
            .Select(p => new { p.Lat, p.Lng, p.SpeedMps, p.HeadingDeg, p.CreatedAtUtc })
            .ToListAsync();
        // Always return JSON shape even when empty.
        return Ok(new { points });
    }

    public record UpsertDriverReq(int? Id, string Name, string Phone, string Pin, VehicleType VehicleType, DriverStatus Status, string? PhotoUrl);

    [HttpPost("drivers")]
    public async Task<IActionResult> UpsertDriver(UpsertDriverReq req)
    {
        Driver d;
        if (req.Id is null)
        {
            d = new Driver();
            _db.Drivers.Add(d);
        }
        else
        {
            d = await _db.Drivers.FirstOrDefaultAsync(x => x.Id == req.Id.Value) ?? new Driver();
            if (d.Id == 0) return NotFound(new { error = "not_found" });
        }

        d.Name = req.Name;
        d.Phone = req.Phone;
        d.Pin = req.Pin;
        d.VehicleType = req.VehicleType;
        d.Status = req.Status;
        d.PhotoUrl = req.PhotoUrl;

        await _db.SaveChangesAsync();
        await _notifyHub.Clients.Group("admin").SendAsync("driver_changed", new { d.Id });
        return Ok(d);
    }

    [HttpDelete("drivers/{id:int}")]
    public async Task<IActionResult> DeleteDriver(int id)
    {
        var d = await _db.Drivers.FirstOrDefaultAsync(x => x.Id == id);
        if (d == null) return NotFound(new { error = "not_found" });

        // لا نحذف السائق إذا كان مرتبطاً بأي طلبات للحفاظ على السجل
        var hasOrders = await _db.Orders.AsNoTracking().AnyAsync(o => o.DriverId == id);
        if (hasOrders)
        {
            return BadRequest(new
            {
                error = "has_orders",
                message = "لا يمكن حذف هذا السائق لأنه مرتبط بطلبات سابقة. يمكنك جعله غير متاح بدلاً من ذلك."
            });
        }

        _db.Drivers.Remove(d);
        try
        {
            await _db.SaveChangesAsync();
            await _notifyHub.Clients.Group("admin").SendAsync("driver_deleted", new { d.Id });
            return Ok(new { ok = true });
        }
        catch (DbUpdateException)
        {
            return BadRequest(new
            {
                error = "delete_failed",
                message = "تعذر حذف السائق لأنه مرتبط ببيانات أخرى."
            });
        }
    }

    /// <param name="deliveredOnly">إذا true تُعاد الطلبات المسلمة فقط (لصفحة الطلبات المسلمة). إذا false أو غير موجود تُعاد الطلبات غير المسلمة (لصفحة الطلبات).</param>
    [HttpGet("orders")]
    public async Task<IActionResult> ListOrders([FromQuery] bool deliveredOnly = false)
    {
        var s = await _db.RestaurantSettings.AsNoTracking().FirstOrDefaultAsync();
        var restaurantLat = s?.RestaurantLat ?? 0.0;
        var restaurantLng = s?.RestaurantLng ?? 0.0;

        var bikeSpeed = (double?)(s?.DriverSpeedBikeKmH) ?? 18.0;
        var carSpeed = (double?)(s?.DriverSpeedCarKmH) ?? 30.0;

        static double HaversineKm(double lat1, double lon1, double lat2, double lon2)
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

        var drivers = await _db.Drivers.AsNoTracking().Select(d => new { d.Id, d.VehicleType }).ToListAsync();
        var driverMap = drivers.ToDictionary(x => x.Id, x => x.VehicleType);

        var raw = await _db.Orders.AsNoTracking()
            .Where(o => deliveredOnly ? o.CurrentStatus == OrderStatus.Delivered : o.CurrentStatus != OrderStatus.Delivered)
            .OrderByDescending(o => o.CreatedAtUtc)
            .Select(o => new { o.Id, o.CustomerId, o.DriverId, o.CurrentStatus, o.Total, o.DeliveryFee, o.DeliveryDistanceKm, o.CreatedAtUtc, o.PrepEtaMinutes, o.DeliveryEtaMinutes, o.ExpectedDeliveryAtUtc, o.LastEtaUpdatedAtUtc, o.DeliveryLat, o.DeliveryLng })
            .ToListAsync();

        var orderIds = raw.Select(x => x.Id).ToList();
        // Edited badge should be true ONLY when the customer actually edited the order,
        // not when the customer created it.
        var customerEditedIds = await _db.OrderStatusHistory.AsNoTracking()
            .Where(h => orderIds.Contains(h.OrderId) &&
                        (h.ReasonCode == "customer_edit" ||
                         (h.Comment != null && h.Comment.Contains("تم تعديل الطلب من قبل الزبون"))))
            .Select(h => h.OrderId)
            .Distinct()
            .ToListAsync();
        var customerEditedSet = customerEditedIds.ToHashSet();

        var adminEditedIds = await _db.OrderStatusHistory.AsNoTracking()
            .Where(h => orderIds.Contains(h.OrderId) &&
                        (h.ChangedByType == "admin" &&
                         (h.Comment != null && h.Comment.Contains("تم تعديل الطلب من قبل الإدارة"))))
            .Select(h => h.OrderId)
            .Distinct()
            .ToListAsync();
        var adminEditedSet = adminEditedIds.ToHashSet();


        // Customer info for list (avoid N+1 in UI)
        var customerIds = raw.Select(x => x.CustomerId).Distinct().ToList();
        var custMap = await _db.Customers.AsNoTracking()
            .Where(c => customerIds.Contains(c.Id))
            .Select(c => new { c.Id, c.Name, c.Phone })
            .ToDictionaryAsync(c => c.Id, c => new { c.Name, c.Phone });

        // Cancellation label (for list badge): "ملغي من قبل الزبون" / "ملغي من قبل السائق" / ...
        var cancelMap = await _db.OrderStatusHistory.AsNoTracking()
            .Where(h => orderIds.Contains(h.OrderId) && h.Status == OrderStatus.Cancelled)
            .GroupBy(h => h.OrderId)
            .Select(g => g.OrderByDescending(x => x.ChangedAtUtc).Select(x => new { x.OrderId, x.Comment }).First())
            .ToDictionaryAsync(x => x.OrderId, x => (x.Comment ?? "").Trim());


        var orders = raw.Select(o =>
        {
            int? approxTravelEtaMinutes = null;
            if (restaurantLat != 0 && restaurantLng != 0 && o.DeliveryLat != 0 && o.DeliveryLng != 0)
            {
                var v = o.DriverId.HasValue && driverMap.TryGetValue(o.DriverId.Value, out var vt) ? vt : VehicleType.Car;
                var speedKmH = v == VehicleType.Bike ? bikeSpeed : carSpeed;
                if (speedKmH <= 0) speedKmH = 30.0;
                var km = HaversineKm(restaurantLat, restaurantLng, o.DeliveryLat, o.DeliveryLng);
                approxTravelEtaMinutes = (int)Math.Max(1, Math.Round((km / speedKmH) * 60.0));
            }
            return new
            {
                o.Id,
                o.CustomerId,
                customerName = custMap.TryGetValue(o.CustomerId, out var cust1) ? (cust1.Name ?? string.Empty) : string.Empty,
                customerPhone = custMap.TryGetValue(o.CustomerId, out var cust2) ? cust2.Phone : null,
                o.DriverId,
                o.CurrentStatus,
                o.Total,
                deliveryFee = o.DeliveryFee,
                deliveryDistanceKm = Math.Round(o.DeliveryDistanceKm, 3),
                o.CreatedAtUtc,
                o.PrepEtaMinutes,
                o.DeliveryEtaMinutes,
                o.ExpectedDeliveryAtUtc,
                o.LastEtaUpdatedAtUtc,
                // IMPORTANT: Order-specific delivery location.
                deliveryLat = o.DeliveryLat,
                deliveryLng = o.DeliveryLng,
                orderType = o.DeliveryLat == 0 && o.DeliveryLng == 0 ? "pickup" : "delivery",
                approxTravelEtaMinutes,
                wasEditedByCustomer = customerEditedSet.Contains(o.Id),
                wasEditedByAdmin = adminEditedSet.Contains(o.Id),
                cancelLabel = cancelMap.TryGetValue(o.Id, out var cancelText) ? cancelText : null
            };
        }).ToList();

        return Ok(orders);
    }

    // Admin order details (for editing)
    [HttpGet("order/{id:int}")]
    public async Task<IActionResult> GetOrder(int id)
    {
        var o = await _db.Orders.AsNoTracking()
            .Include(x => x.Items)
            .Include(x => x.StatusHistory)
            .FirstOrDefaultAsync(x => x.Id == id);
        if (o == null) return NotFound(new { error = "not_found" });

        var cust = await _db.Customers.AsNoTracking().FirstOrDefaultAsync(c => c.Id == o.CustomerId);

        var productIds = o.Items.Where(i => i.ProductId > 0).Select(i => i.ProductId).Distinct().ToList();
        List<(int Id, int CategoryId, string CatName)> productCategoryMap;
        if (productIds.Count == 0)
        {
            productCategoryMap = new List<(int Id, int CategoryId, string CatName)>();
        }
        else
        {
            var raw = await _db.Products.AsNoTracking()
                .Where(p => productIds.Contains(p.Id))
                .Include(p => p.Category)
                .Select(p => new { p.Id, p.CategoryId, CatName = p.Category != null ? p.Category.Name : (string?)null })
                .ToListAsync();
            productCategoryMap = raw.Select(x => (x.Id, x.CategoryId, CatName: x.CatName ?? "")).ToList();
        }
        var productCategoryNames = productCategoryMap.ToDictionary(x => x.Id, x => x.CatName);
        var productCategoryIds = productCategoryMap.ToDictionary(x => x.Id, x => x.CategoryId);
        var categoryNamesById = productCategoryMap
            .GroupBy(x => x.CategoryId)
            .ToDictionary(g => g.Key, g => g.First().CatName);

        // Map offers to their primary category so that section printers
        // (kitchen printers) can route offers just like normal products.
        var offerIds = o.Items.Where(i => i.ProductId < 0)
            .Select(i => Math.Abs(i.ProductId))
            .Distinct()
            .ToList();
        Dictionary<int, int> offerPrimaryCategoryMap = new();
        if (offerIds.Count > 0)
        {
            var offerCategories = await _db.OfferCategories.AsNoTracking()
                .Where(oc => offerIds.Contains(oc.OfferId))
                .GroupBy(oc => oc.OfferId)
                .ToListAsync();

            offerPrimaryCategoryMap = offerCategories
                .ToDictionary(
                    g => g.Key,
                    g => g.Select(x => x.CategoryId).FirstOrDefault()
                );
        }

        return Ok(new
        {
            o.Id,
            o.CustomerId,
            customerName = cust?.Name,
            customerPhone = cust?.Phone,
            o.CurrentStatus,
            o.Notes,
            o.DeliveryLat,
            o.DeliveryLng,
            o.DeliveryAddress,
            o.Subtotal,
            o.DeliveryFee,
            o.Total,
            createdAtUtc = o.CreatedAtUtc,
            deliveryDistanceKm = Math.Round(o.DeliveryDistanceKm, 3),
            orderType = o.OrderType ?? (o.DeliveryLat == 0 && o.DeliveryLng == 0 ? "pickup" : "delivery"),
            paymentMethod = "نقدي",
            items = o.Items.Select(i =>
            {
                int? catId = null;
                string? catName = null;

                if (i.ProductId > 0)
                {
                    if (productCategoryIds.TryGetValue(i.ProductId, out var pid))
                    {
                        catId = pid;
                        if (categoryNamesById.TryGetValue(pid, out var n))
                            catName = n;
                    }
                }
                else if (i.ProductId < 0)
                {
                    var offerId = Math.Abs(i.ProductId);
                    if (offerPrimaryCategoryMap.TryGetValue(offerId, out var ocid))
                    {
                        catId = ocid;
                        if (categoryNamesById.TryGetValue(ocid, out var n))
                            catName = n;
                    }
                }

                return new
                {
                    i.ProductId,
                    i.ProductNameSnapshot,
                    i.UnitPriceSnapshot,
                    i.Quantity,
                    i.OptionsSnapshot,
                    categoryName = catName,
                    categoryId = catId
                };
            }),
            history = o.StatusHistory.OrderBy(h => h.ChangedAtUtc).Select(h => new { h.Status, h.ChangedByType, h.Comment, h.ChangedAtUtc })
        });
    }

    public record AdminEditOrderItemReq(int ProductId, int Quantity, string? OptionsSnapshot);
    public record AdminEditOrderRequest(List<AdminEditOrderItemReq> Items, string? Notes, double? DeliveryLat, double? DeliveryLng, string? DeliveryAddress, decimal? DeliveryFee);

    /// <summary>
    /// Admin can edit an order at any time (no time window), except Delivered/Cancelled.
    /// Supports both product items (ProductId &gt; 0) and offers (ProductId &lt; 0 where abs(ProductId)=OfferId).
    /// </summary>
    [HttpPost("order/{id:int}/edit")]
    public async Task<IActionResult> AdminEditOrder(int id, AdminEditOrderRequest req)
    {
        var o = await _db.Orders
            .Include(x => x.Items)
            .FirstOrDefaultAsync(x => x.Id == id);
        if (o == null) return NotFound(new { error = "not_found" });

        if (o.CurrentStatus == OrderStatus.Delivered || o.CurrentStatus == OrderStatus.Cancelled)
            return BadRequest(new { error = "not_editable", message = "لا يمكن تعديل هذا الطلب" });

        if (req.Items == null || req.Items.Count == 0)
            return BadRequest(new { error = "empty_items", message = "لا يمكن أن يكون الطلب فارغاً" });

        // Gather ids
        var productIds = req.Items.Where(i => i.ProductId > 0).Select(i => i.ProductId).Distinct().ToList();
        var offerIds = req.Items.Where(i => i.ProductId < 0).Select(i => Math.Abs(i.ProductId)).Distinct().ToList();

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
            : await _db.Products.Where(p => productIds.Contains(p.Id)).ToListAsync();

        var offers = (offerIds.Count == 0)
            ? new List<Offer>()
            : await _db.Offers.AsNoTracking().Where(x => offerIds.Contains(x.Id)).ToListAsync();

        // Variants/Addons for all involved products (including linked offer products)
        var variants = (productIds.Count == 0)
            ? new List<ProductVariant>()
            : await _db.ProductVariants.AsNoTracking().Where(v => productIds.Contains(v.ProductId)).ToListAsync();
        var addons = (productIds.Count == 0)
            ? new List<ProductAddon>()
            : await _db.ProductAddons.AsNoTracking().Where(a => productIds.Contains(a.ProductId)).ToListAsync();

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

        // Build new items
        var newItems = new List<OrderItem>();
        decimal subtotalAfter = 0;
        decimal subtotalBefore = 0;

        foreach (var it in req.Items)
        {
            if (it.Quantity <= 0) continue;

            if (it.ProductId > 0)
            {
                var p = products.FirstOrDefault(x => x.Id == it.ProductId);
                if (p == null) return BadRequest(new { error = "invalid_items", message = "بعض الأصناف غير صحيحة" });

                // Parse options snapshot (supports name/Name etc.)
                int? variantId = null;
                List<int> addonIds = new();
                string? noteText = null;
                if (!string.IsNullOrWhiteSpace(it.OptionsSnapshot))
                {
                    try
                    {
                        using var doc = JsonDocument.Parse(it.OptionsSnapshot);
                        var root = doc.RootElement;

                        if (root.TryGetProperty("variantId", out var v1) && v1.ValueKind == JsonValueKind.Number) variantId = v1.GetInt32();
                        else if (root.TryGetProperty("VariantId", out var v2) && v2.ValueKind == JsonValueKind.Number) variantId = v2.GetInt32();

                        if (root.TryGetProperty("addonIds", out var a1) && a1.ValueKind == JsonValueKind.Array)
                            addonIds = a1.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.Number).Select(x => x.GetInt32()).ToList();
                        else if (root.TryGetProperty("AddonIds", out var a2) && a2.ValueKind == JsonValueKind.Array)
                            addonIds = a2.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.Number).Select(x => x.GetInt32()).ToList();

                        if (root.TryGetProperty("note", out var n1) && n1.ValueKind == JsonValueKind.String) noteText = n1.GetString();
                        else if (root.TryGetProperty("Note", out var n2) && n2.ValueKind == JsonValueKind.String) noteText = n2.GetString();
                    }
                    catch { /* ignore invalid snapshot */ }
                }

                var baseOriginal = p.Price;
                var d = BestDiscountForProduct(p.Id, p.CategoryId, baseOriginal);
                var baseAfter = d.finalBasePrice;

                decimal variantDelta = 0;
                string? variantName = null;
                if (variantId.HasValue)
                {
                    var v = variants.FirstOrDefault(x => x.Id == variantId.Value && x.ProductId == p.Id && x.IsActive);
                    if (v != null)
                    {
                        variantDelta = v.PriceDelta;
                        variantName = v.Name;
                    }
                }

                decimal addonsDelta = 0;
                var chosenAddons = new List<object>();
                foreach (var aid in addonIds.Distinct())
                {
                    var a = addons.FirstOrDefault(x => x.Id == aid && x.ProductId == p.Id && x.IsActive);
                    if (a == null) continue;
                    addonsDelta += a.Price;
                    chosenAddons.Add(new { a.Id, a.Name, a.Price });
                }

                var unitBefore = baseOriginal + variantDelta + addonsDelta;
                var unitAfter = baseAfter + variantDelta + addonsDelta;

                subtotalBefore += unitBefore * it.Quantity;
                subtotalAfter += unitAfter * it.Quantity;

                // Normalize snapshot for printing
                var snap = JsonSerializer.Serialize(new
                {
                    variantId,
                    variantName,
                    variantDelta,
                    addonIds = addonIds.Distinct().ToList(),
                    addons = chosenAddons,
                    note = string.IsNullOrWhiteSpace(noteText) ? null : noteText.Trim(),
                    discount = new { baseOriginal, baseAfter, percent = d.percent, badge = d.badgeText }
                });

                newItems.Add(new OrderItem
                {
                    OrderId = o.Id,
                    ProductId = p.Id,
                    ProductNameSnapshot = p.Name,
                    UnitPriceSnapshot = unitAfter,
                    Quantity = it.Quantity,
                    OptionsSnapshot = snap
                });
            }
            else
            {
                var offerId = Math.Abs(it.ProductId);
                var off = offers.FirstOrDefault(x => x.Id == offerId);
                if (off == null) return BadRequest(new { error = "invalid_items", message = "بعض العروض غير صحيحة" });

                // Optional: allow offer to behave like linked product for variants/addons
                int? templateProductId = offerPrimaryProduct.ContainsKey(offerId) ? offerPrimaryProduct[offerId] : (int?)null;
                int? variantId = null;
                List<int> addonIds = new();
                string? noteText = null;

                if (!string.IsNullOrWhiteSpace(it.OptionsSnapshot))
                {
                    try
                    {
                        using var doc = JsonDocument.Parse(it.OptionsSnapshot);
                        var root = doc.RootElement;
                        if (root.TryGetProperty("variantId", out var v1) && v1.ValueKind == JsonValueKind.Number) variantId = v1.GetInt32();
                        else if (root.TryGetProperty("VariantId", out var v2) && v2.ValueKind == JsonValueKind.Number) variantId = v2.GetInt32();

                        if (root.TryGetProperty("addonIds", out var a1) && a1.ValueKind == JsonValueKind.Array)
                            addonIds = a1.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.Number).Select(x => x.GetInt32()).ToList();
                        else if (root.TryGetProperty("AddonIds", out var a2) && a2.ValueKind == JsonValueKind.Array)
                            addonIds = a2.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.Number).Select(x => x.GetInt32()).ToList();

                        if (root.TryGetProperty("note", out var n1) && n1.ValueKind == JsonValueKind.String) noteText = n1.GetString();
                        else if (root.TryGetProperty("Note", out var n2) && n2.ValueKind == JsonValueKind.String) noteText = n2.GetString();
                    }
                    catch { }
                }

                decimal variantDelta = 0;
                string? variantName = null;
                decimal addonsDelta = 0;
                var chosenAddons = new List<object>();

                if (templateProductId.HasValue && templateProductId.Value > 0)
                {
                    if (variantId.HasValue)
                    {
                        var v = variants.FirstOrDefault(x => x.Id == variantId.Value && x.ProductId == templateProductId.Value && x.IsActive);
                        if (v != null) { variantDelta = v.PriceDelta; variantName = v.Name; }
                    }
                    foreach (var aid in addonIds.Distinct())
                    {
                        var a = addons.FirstOrDefault(x => x.Id == aid && x.ProductId == templateProductId.Value && x.IsActive);
                        if (a == null) continue;
                        addonsDelta += a.Price;
                        chosenAddons.Add(new { a.Id, a.Name, a.Price });
                    }
                }

	            // Offer base price: prefer PriceAfter, then PriceBefore.
	            // If the offer is linked to a product and pricing is missing, fall back to that product's price.
	            decimal offerBasePrice = off.PriceAfter ?? off.PriceBefore ?? 0m;
	            if (offerBasePrice <= 0m && templateProductId.HasValue && templateProductId.Value > 0)
	            {
	                var tp = products.FirstOrDefault(p => p.Id == templateProductId.Value);
	                if (tp != null) offerBasePrice = tp.Price;
	            }

	            decimal unit = offerBasePrice + variantDelta + addonsDelta;
                subtotalBefore += unit * it.Quantity;
                subtotalAfter += unit * it.Quantity;

                var snap = JsonSerializer.Serialize(new
                {
                    isOffer = true,
                    offerId,
                    variantId,
                    variantName,
                    variantDelta,
                    addonIds = addonIds.Distinct().ToList(),
                    addons = chosenAddons,
                    note = string.IsNullOrWhiteSpace(noteText) ? null : noteText.Trim()
                });

                newItems.Add(new OrderItem
                {
                    OrderId = o.Id,
                    ProductId = -offerId,
                    ProductNameSnapshot = off.Title,
                    UnitPriceSnapshot = unit,
                    Quantity = it.Quantity,
                    OptionsSnapshot = snap
                });
            }
        }

        if (newItems.Count == 0)
            return BadRequest(new { error = "empty_items", message = "لا يمكن أن يكون الطلب فارغاً" });

        // Delivery location update (optional)
        if (req.DeliveryLat != null && req.DeliveryLng != null)
        {
            var lat = req.DeliveryLat.Value;
            var lng = req.DeliveryLng.Value;
            if (lat < -90 || lat > 90 || lng < -180 || lng > 180)
                return BadRequest(new { error = "invalid_location", message = "الموقع غير صحيح" });
            o.DeliveryLat = lat;
            o.DeliveryLng = lng;
        }
        if (!string.IsNullOrWhiteSpace(req.DeliveryAddress)) o.DeliveryAddress = req.DeliveryAddress.Trim();
        if (req.DeliveryFee.HasValue) o.DeliveryFee = Math.Max(0, req.DeliveryFee.Value);

        o.Notes = string.IsNullOrWhiteSpace(req.Notes) ? null : req.Notes.Trim();
        o.Subtotal = subtotalAfter;
        o.TotalBeforeDiscount = subtotalBefore + o.DeliveryFee;
        o.CartDiscount = Math.Max(0, subtotalBefore - subtotalAfter);
        o.Total = subtotalAfter + o.DeliveryFee;

        // History entry
        o.StatusHistory.Add(new OrderStatusHistory
        {
            OrderId = o.Id,
            Status = o.CurrentStatus,
            ChangedAtUtc = DateTime.UtcNow,
            ChangedByType = "admin",
            Comment = "تم تعديل الطلب من قبل الإدارة"
        });

        _db.OrderItems.RemoveRange(o.Items);
        await _db.SaveChangesAsync();
        _db.OrderItems.AddRange(newItems);
        await _db.SaveChangesAsync();

        await _notifyHub.Clients.Group("admin").SendAsync("order_status", new { orderId = o.Id, status = o.CurrentStatus.ToString() });

        return Ok(new { ok = true, orderId = o.Id, o.Subtotal, o.DeliveryFee, o.Total });
    }

    [HttpGet("customers")]
    public async Task<IActionResult> ListCustomers([FromQuery] string? search)
    {
        var query = _db.Customers.AsNoTracking().OrderByDescending(c => c.Id);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var term = search.Trim();
            query = query.Where(c =>
                (c.Name != null && c.Name.Contains(term)) ||
                (c.Phone != null && c.Phone.Contains(term))).OrderByDescending(c => c.Id);
        }
        var list = await query
            .Select(c => new {
                c.Id,
                c.Name,
                c.Phone,
                c.Email,
                c.DefaultAddress,
                c.DefaultLat,
                c.DefaultLng,
                c.LastLat,
                c.LastLng,
                c.IsChatBlocked,
                c.IsAppBlocked,
                c.CreatedAtUtc
            })
            .ToListAsync();
        return Ok(new { customers = list });
    }

    // Chat: ensure ONE thread per customer (market requirement)
    [HttpGet("chat-thread/{customerId:int}")]
    public async Task<IActionResult> GetOrCreateChatThread(int customerId)
    {
        var customer = await _db.Customers.FirstOrDefaultAsync(c => c.Id == customerId);
        if (customer == null) return NotFound(new { error = "not_found" });

        var now = DateTime.UtcNow;
        var thread = await _db.ComplaintThreads
            .OrderByDescending(t => t.UpdatedAtUtc)
            .FirstOrDefaultAsync(t => t.CustomerId == customerId);

        if (thread == null)
        {
            thread = new ComplaintThread
            {
                CustomerId = customerId,
                OrderId = null,
                Title = "دردشة مع المطعم",
                UpdatedAtUtc = now,
                CreatedAtUtc = now,
                LastAdminSeenAtUtc = now
            };
            _db.ComplaintThreads.Add(thread);
            await _db.SaveChangesAsync();

            // Let admin UIs refresh lists if needed
            await _notifyHub.Clients.Group("admin").SendAsync("complaint_new", new { thread.Id, thread.Title, thread.CustomerId, thread.OrderId });
        }

        return Ok(new { threadId = thread.Id, customerId, customerName = customer.Name, isChatBlocked = customer.IsChatBlocked });
    }

    public record ChatBlockReq(bool Blocked);

    [HttpPost("customers/{customerId:int}/chat-block")]
    public async Task<IActionResult> SetCustomerChatBlock(int customerId, ChatBlockReq req)
    {
        var customer = await _db.Customers.FirstOrDefaultAsync(c => c.Id == customerId);
        if (customer == null) return NotFound(new { error = "not_found" });

        customer.IsChatBlocked = req.Blocked;
        await _db.SaveChangesAsync();

        var payload = new { customerId, isChatBlocked = customer.IsChatBlocked };
        await _notifyHub.Clients.Group("admin").SendAsync("chat_blocked", payload);
        await _notifyHub.Clients.Group($"customer-{customerId}").SendAsync("chat_blocked", payload);

        return Ok(new { ok = true, customerId, isChatBlocked = customer.IsChatBlocked });
    }

    public record AppBlockReq(bool Blocked);

    [HttpPost("customers/{customerId:int}/app-block")]
    public async Task<IActionResult> SetCustomerAppBlock(int customerId, AppBlockReq req)
    {
        var customer = await _db.Customers.FirstOrDefaultAsync(c => c.Id == customerId);
        if (customer == null) return NotFound(new { error = "not_found" });

        customer.IsAppBlocked = req.Blocked;
        await _db.SaveChangesAsync();

        // notify admin dashboards if open
        var payload = new { customerId, isAppBlocked = customer.IsAppBlocked };
        await _notifyHub.Clients.Group("admin").SendAsync("app_blocked", payload);
        await _notifyHub.Clients.Group($"customer-{customerId}").SendAsync("app_blocked", payload);

        return Ok(new { ok = true, customerId, isAppBlocked = customer.IsAppBlocked });
    }

    /// <summary>
    /// حذف حساب الزبون نهائياً (مع كل الطلبات والعناوين والدردشات والتقييمات والإشعارات وأجهزته).
    /// يُبلّغ تطبيق الزبون فوراً عبر SignalR (account_deleted) ثم يُحذف المستخدم من Firebase Auth.
    /// </summary>
    [HttpDelete("customers/{id:int}")]
    public async Task<IActionResult> DeleteCustomer(int id)
    {
        var customer = await _db.Customers.FirstOrDefaultAsync(c => c.Id == id);
        if (customer == null) return NotFound(new { error = "not_found" });

        var firebaseUid = customer.FirebaseUid?.Trim();

        // 1) إبلاغ تطبيق الزبون فوراً لتسجيل الخروج (قبل حذف أي بيانات)
        await _notifyHub.Clients.Group($"customer-{id}").SendAsync("account_deleted", new { customerId = id });

        // 2) حذف المستخدم من Firebase Authentication إن وُجد
        if (!string.IsNullOrEmpty(firebaseUid))
            await _firebase.DeleteUserAsync(firebaseUid);

        var orderIds = await _db.Orders.Where(o => o.CustomerId == id).Select(o => o.Id).ToListAsync();

        foreach (var orderId in orderIds)
        {
            var o = await _db.Orders.Include(x => x.Items).Include(x => x.StatusHistory).FirstOrDefaultAsync(x => x.Id == orderId);
            if (o == null) continue;
            var or = await _db.OrderRatings.FirstOrDefaultAsync(r => r.OrderId == orderId);
            if (or != null) _db.OrderRatings.Remove(or);
            var threads = await _db.ComplaintThreads.Where(t => t.OrderId == orderId).ToListAsync();
            foreach (var t in threads)
            {
                var msgs = await _db.ComplaintMessages.Where(m => m.ThreadId == t.Id).ToListAsync();
                _db.ComplaintMessages.RemoveRange(msgs);
            }
            _db.ComplaintThreads.RemoveRange(threads);
            _db.OrderStatusHistory.RemoveRange(o.StatusHistory);
            _db.OrderItems.RemoveRange(o.Items);
            _db.Orders.Remove(o);
        }

        var customerThreads = await _db.ComplaintThreads.Where(t => t.CustomerId == id).ToListAsync();
        foreach (var t in customerThreads)
        {
            var msgs = await _db.ComplaintMessages.Where(m => m.ThreadId == t.Id).ToListAsync();
            _db.ComplaintMessages.RemoveRange(msgs);
        }
        _db.ComplaintThreads.RemoveRange(customerThreads);

        var ratings = await _db.Ratings.Where(r => r.CustomerId == id).ToListAsync();
        _db.Ratings.RemoveRange(ratings);

        var addresses = await _db.CustomerAddresses.Where(a => a.CustomerId == id).ToListAsync();
        _db.CustomerAddresses.RemoveRange(addresses);

        var notifs = await _db.Notifications.Where(n => n.UserType == NotificationUserType.Customer && n.UserId == id).ToListAsync();
        _db.Notifications.RemoveRange(notifs);

        var tokens = await _db.DeviceTokens.Where(t => t.UserType == DeviceUserType.Customer && t.UserId == id).ToListAsync();
        _db.DeviceTokens.RemoveRange(tokens);

        _db.Customers.Remove(customer);
        await _db.SaveChangesAsync();

        return Ok(new { ok = true });
    }

    [HttpGet("customers/{customerId:int}/details")]
    public async Task<IActionResult> GetCustomerDetails(int customerId)
    {
        var customer = await _db.Customers.AsNoTracking().FirstOrDefaultAsync(c => c.Id == customerId);
        if (customer == null) return NotFound();

        var orders = await _db.Orders
            .AsNoTracking()
            .Include(o => o.Items)
            .Where(o => o.CustomerId == customerId)
            .OrderByDescending(o => o.CreatedAtUtc)
            .Take(50)
            .ToListAsync();

        var orderIds = orders.Select(o => o.Id).ToList();
        var ratings = await _db.OrderRatings
            .AsNoTracking()
            .Where(r => orderIds.Contains(r.OrderId))
            .ToListAsync();
        var ratingByOrder = ratings.ToDictionary(r => r.OrderId, r => r);

        var shapedOrders = orders.Select(o => new
        {
            id = o.Id,
            status = o.CurrentStatus.ToString(),
            total = o.Total,
            subtotal = o.Subtotal,
            deliveryFee = o.DeliveryFee,
            cartDiscount = o.CartDiscount,
            totalBeforeDiscount = o.TotalBeforeDiscount,
            createdAtUtc = o.CreatedAtUtc,
            editableUntilUtc = o.OrderEditableUntilUtc,
            notes = o.Notes,
            deliveryAddress = o.DeliveryAddress,
            items = o.Items.Select(i => new
            {
                id = i.Id,
                productId = i.ProductId,
                name = i.ProductNameSnapshot,
                qty = i.Quantity,
                unit = i.UnitPriceSnapshot,
                options = i.OptionsSnapshot
            }),
            orderRating = ratingByOrder.TryGetValue(o.Id, out var rr) ? new
            {
                restaurantRate = rr.RestaurantRate,
                driverRate = rr.DriverRate,
                comment = rr.Comment,
                createdAtUtc = rr.CreatedAtUtc
            } : null
        });

        return Ok(new
        {
            customer = new
            {
                id = customer.Id,
                name = customer.Name,
                phone = customer.Phone,
                createdAtUtc = customer.CreatedAtUtc,
                isChatBlocked = customer.IsChatBlocked
            },
            orders = shapedOrders
        });
    }

    [HttpGet("reports/summary")]
    public async Task<IActionResult> ReportsSummary()
    {
        var now = DateTime.UtcNow;
        var today = new DateTime(now.Year, now.Month, now.Day, 0, 0, 0, DateTimeKind.Utc);
        var tomorrow = today.AddDays(1);
        // Delivered only (based on DeliveredAtUtc)
        var todayOrders = await _db.Orders.AsNoTracking()
            .Where(o => o.CurrentStatus == OrderStatus.Delivered && o.DeliveredAtUtc != null && o.DeliveredAtUtc >= today && o.DeliveredAtUtc < tomorrow)
            .ToListAsync();
        var salesToday = todayOrders.Sum(o => o.Total);
        var ordersCount = todayOrders.Count;

        // Avg prep/delivery from ETA fields on delivered orders
        var delivered = todayOrders;
        double? avgPrep = null;
        double? avgDel = null;
        if (delivered.Count > 0)
        {
            avgPrep = delivered.Where(o => o.PrepEtaMinutes != null).Select(o => (double)o.PrepEtaMinutes!.Value).DefaultIfEmpty().Average();
            avgDel = delivered.Where(o => o.DeliveryEtaMinutes != null).Select(o => (double)o.DeliveryEtaMinutes!.Value).DefaultIfEmpty().Average();
        }

        var topProducts = await _db.OrderItems.AsNoTracking()
            .Where(oi => _db.Orders.Any(o => o.Id == oi.OrderId
                                            && o.CurrentStatus == OrderStatus.Delivered
                                            && o.DeliveredAtUtc != null
                                            && o.DeliveredAtUtc >= today
                                            && o.DeliveredAtUtc < tomorrow))
            .GroupBy(oi => oi.ProductNameSnapshot)
            .Select(g => new { name = g.Key, qty = g.Sum(x => x.Quantity) })
            .OrderByDescending(x => x.qty)
            .Take(10)
            .ToListAsync();

        var settings = await _db.RestaurantSettings.AsNoTracking().FirstOrDefaultAsync();
        var restaurantName = settings?.RestaurantName?.Trim() ?? "مطعم توب شيف";
        return Ok(new { salesToday, ordersCount, avgPrepEtaMinutes = avgPrep, avgDeliveryEtaMinutes = avgDel, topProducts, restaurantName });
    }

    [HttpGet("reports/weekly-summary")]
    public async Task<IActionResult> ReportsWeeklySummary()
    {
        var now = DateTime.UtcNow;
        var end = new DateTime(now.Year, now.Month, now.Day, 0, 0, 0, DateTimeKind.Utc).AddDays(1);
        var start = end.AddDays(-7);
        var payload = await BuildRangeSummary(start, end);
        return Ok(payload);
    }

    [HttpGet("reports/monthly-summary")]
    public async Task<IActionResult> ReportsMonthlySummary()
    {
        var now = DateTime.UtcNow;
        var start = new DateTime(now.Year, now.Month, 1, 0, 0, 0, DateTimeKind.Utc);
        var end = start.AddMonths(1);
        var payload = await BuildRangeSummary(start, end);
        return Ok(payload);
    }

    /// <summary>
    /// Builds a delivered-orders summary between [startUtc, endUtc).
    /// Used by weekly/monthly reports and charts.
    /// </summary>
    private async Task<object> BuildRangeSummary(DateTime startUtc, DateTime endUtc)
    {
        // Delivered only (based on DeliveredAtUtc)
        var deliveredOrders = await _db.Orders.AsNoTracking()
            .Where(o => o.CurrentStatus == OrderStatus.Delivered
                        && o.DeliveredAtUtc != null
                        && o.DeliveredAtUtc >= startUtc
                        && o.DeliveredAtUtc < endUtc)
            .Select(o => new
            {
                o.Id,
                o.Total,
                o.DriverId,
                o.DriverConfirmedAtUtc,
                o.DeliveredAtUtc,
                o.DistanceKm
            })
            .ToListAsync();

        var ordersCount = deliveredOrders.Count;
        var sales = deliveredOrders.Sum(o => o.Total);

        double? avgDeliveryMinutes = null;
        var withTimes = deliveredOrders.Where(o => o.DriverConfirmedAtUtc != null && o.DeliveredAtUtc != null).ToList();
        if (withTimes.Count > 0)
            avgDeliveryMinutes = withTimes.Average(x => (x.DeliveredAtUtc!.Value - x.DriverConfirmedAtUtc!.Value).TotalMinutes);

        // Daily breakdown for charts
        var daily = deliveredOrders
            .GroupBy(o => o.DeliveredAtUtc!.Value.Date)
            .OrderBy(g => g.Key)
            .Select(g => new
            {
                dateUtc = g.Key,
                ordersCount = g.Count(),
                sales = g.Sum(x => x.Total)
            })
            .ToList();

        // Top products by revenue in the range
        var topProducts = await (from oi in _db.OrderItems.AsNoTracking()
                                 join o in _db.Orders.AsNoTracking() on oi.OrderId equals o.Id
                                 where o.CurrentStatus == OrderStatus.Delivered
                                       && o.DeliveredAtUtc != null
                                       && o.DeliveredAtUtc >= startUtc
                                       && o.DeliveredAtUtc < endUtc
                                 group oi by oi.ProductNameSnapshot into g
                                 select new
                                 {
                                     name = g.Key,
                                     qty = g.Sum(x => x.Quantity),
                                     revenue = g.Sum(x => x.UnitPriceSnapshot * x.Quantity)
                                 })
            .OrderByDescending(x => x.revenue)
            .Take(10)
            .ToListAsync();

        // Top drivers in the range
        var byDriver = deliveredOrders
            .Where(o => o.DriverId != null)
            .GroupBy(o => o.DriverId!.Value)
            .Select(g => new
            {
                driverId = g.Key,
                deliveredCount = g.Count(),
                totalAmount = g.Sum(x => x.Total),
                totalDistanceKm = g.Sum(x => Math.Max(0.0, x.DistanceKm)),
                avgDeliveryMinutes = g.Where(x => x.DriverConfirmedAtUtc != null && x.DeliveredAtUtc != null)
                    .Select(x => (x.DeliveredAtUtc!.Value - x.DriverConfirmedAtUtc!.Value).TotalMinutes)
                    .DefaultIfEmpty()
                    .Average()
            })
            .OrderByDescending(x => x.totalAmount)
            .Take(10)
            .ToList();

        var driverIds = byDriver.Select(x => x.driverId).ToList();
        var drivers = await _db.Drivers.AsNoTracking()
            .Where(d => driverIds.Contains(d.Id))
            .Select(d => new { d.Id, d.Name, d.Phone })
            .ToListAsync();
        var driverMap = drivers.ToDictionary(d => d.Id);

        var topDrivers = byDriver.Select(x => new
        {
            x.driverId,
            driverName = driverMap.TryGetValue(x.driverId, out var d) ? d.Name : $"#{x.driverId}",
            driverPhone = driverMap.TryGetValue(x.driverId, out var d2) ? d2.Phone : "",
            x.deliveredCount,
            x.totalAmount,
            x.totalDistanceKm,
            x.avgDeliveryMinutes
        }).ToList();

        var settings = await _db.RestaurantSettings.AsNoTracking().FirstOrDefaultAsync();
        var restaurantName = settings?.RestaurantName?.Trim() ?? "مطعم توب شيف";
        return new
        {
            startUtc,
            endUtc,
            sales,
            ordersCount,
            avgDeliveryEtaMinutes = avgDeliveryMinutes,
            daily,
            topProducts,
            topDrivers,
            restaurantName
        };
    }

    [HttpGet("reports/products-daily")]
    public async Task<IActionResult> ReportsProductsDaily()
    {
        var now = DateTime.UtcNow;
        var today = new DateTime(now.Year, now.Month, now.Day, 0, 0, 0, DateTimeKind.Utc);
        var tomorrow = today.AddDays(1);

        // Delivered only
        var q = from oi in _db.OrderItems.AsNoTracking()
                join o in _db.Orders.AsNoTracking() on oi.OrderId equals o.Id
                where o.DeliveredAtUtc != null && o.DeliveredAtUtc >= today && o.DeliveredAtUtc < tomorrow
                      && o.CurrentStatus == OrderStatus.Delivered
                select new { oi.ProductNameSnapshot, oi.UnitPriceSnapshot, oi.Quantity };

        var rows = await q
            .GroupBy(x => x.ProductNameSnapshot)
            .Select(g => new
            {
                name = g.Key,
                qty = g.Sum(x => x.Quantity),
                revenue = g.Sum(x => x.UnitPriceSnapshot * x.Quantity)
            })
            .OrderByDescending(x => x.revenue)
            .ToListAsync();

        return Ok(rows);
    }

    private static double HaversineKm(double lat1, double lon1, double lat2, double lon2)
    {
        const double R = 6371.0;
        static double ToRad(double deg) => deg * (Math.PI / 180.0);
        var dLat = ToRad(lat2 - lat1);
        var dLon = ToRad(lon2 - lon1);
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(ToRad(lat1)) * Math.Cos(ToRad(lat2)) *
                Math.Sin(dLon / 2) * Math.Sin(dLon / 2);
        var c = 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
        return R * c;
    }

    [HttpGet("reports/drivers-daily")]
    public async Task<IActionResult> ReportsDriversDaily()
    {
        var now = DateTime.UtcNow;
        var today = new DateTime(now.Year, now.Month, now.Day, 0, 0, 0, DateTimeKind.Utc);
        var tomorrow = today.AddDays(1);

        var s = await _db.RestaurantSettings.AsNoTracking().FirstOrDefaultAsync();
        var rLat = s?.RestaurantLat ?? 0.0;
        var rLng = s?.RestaurantLng ?? 0.0;

        var delivered = await _db.Orders.AsNoTracking()
            .Where(o => o.DriverId != null && o.CurrentStatus == OrderStatus.Delivered && o.DeliveredAtUtc != null && o.DeliveredAtUtc >= today && o.DeliveredAtUtc < tomorrow)
            .Select(o => new { o.Id, o.DriverId, o.Total, o.DistanceKm, o.DriverConfirmedAtUtc, o.DeliveredAtUtc, o.DeliveryLat, o.DeliveryLng })
            .ToListAsync();

        var driverIds = delivered.Select(x => x.DriverId!.Value).Distinct().ToList();
        var drivers = await _db.Drivers.AsNoTracking()
            .Where(d => driverIds.Contains(d.Id))
            .Select(d => new { d.Id, d.Name, d.Phone })
            .ToListAsync();
        var byId = drivers.ToDictionary(d => d.Id);

        var rows = delivered
            .GroupBy(o => o.DriverId!.Value)
            .Select(g =>
            {
                var d = byId.TryGetValue(g.Key, out var dd) ? dd : new { Id = g.Key, Name = $"#{g.Key}", Phone = "" };
                var actualDist = g.Sum(x => Math.Max(0.0, x.DistanceKm));
                var withTimes = g.Where(x => x.DriverConfirmedAtUtc != null && x.DeliveredAtUtc != null).ToList();
                double? avgMin = null;
                if (withTimes.Count > 0)
                    avgMin = withTimes.Average(x => (x.DeliveredAtUtc!.Value - x.DriverConfirmedAtUtc!.Value).TotalMinutes);
                return new
                {
                    driverId = g.Key,
                    driverName = d.Name,
                    driverPhone = d.Phone,
                    deliveredCount = g.Count(),
                    totalAmount = g.Sum(x => x.Total),
                    avgDeliveryMinutes = avgMin,
                    totalDistanceKm = Math.Round(actualDist, 3)
                };
            })
            .OrderByDescending(x => x.deliveredCount)
            .ThenByDescending(x => x.totalAmount)
            .ToList();

        return Ok(rows);
    }

    [HttpGet("reports/top")]
    public async Task<IActionResult> ReportsTop()
    {
        var now = DateTime.UtcNow;
        var today = new DateTime(now.Year, now.Month, now.Day, 0, 0, 0, DateTimeKind.Utc);
        var tomorrow = today.AddDays(1);

        // Delivered only (DeliveredAtUtc + CurrentStatus)
        var topProducts = await _db.OrderItems.AsNoTracking()
            .Where(oi => _db.Orders.Any(o => o.Id == oi.OrderId
                                            && o.CurrentStatus == OrderStatus.Delivered
                                            && o.DeliveredAtUtc != null
                                            && o.DeliveredAtUtc >= today
                                            && o.DeliveredAtUtc < tomorrow))
            .GroupBy(oi => oi.ProductNameSnapshot)
            .Select(g => new { name = g.Key, qty = g.Sum(x => x.Quantity), revenue = g.Sum(x => x.UnitPriceSnapshot * x.Quantity) })
            .OrderByDescending(x => x.revenue)
            .Take(10)
            .ToListAsync();

        // Driver report with average delivery time (DeliveredAt - DriverConfirmedAt)
        var deliveredOrders = await _db.Orders.AsNoTracking()
            .Where(o => o.DriverId != null
                        && o.CurrentStatus == OrderStatus.Delivered
                        && o.DeliveredAtUtc != null
                        && o.DeliveredAtUtc >= today
                        && o.DeliveredAtUtc < tomorrow)
            .Select(o => new { o.DriverId, o.Total, o.DistanceKm, o.DriverConfirmedAtUtc, o.DeliveredAtUtc })
            .ToListAsync();

        var topDrivers = deliveredOrders
            .GroupBy(o => o.DriverId!.Value)
            .Select(g =>
            {
                var withTimes = g.Where(x => x.DriverConfirmedAtUtc != null && x.DeliveredAtUtc != null).ToList();
                double? avgMin = null;
                if (withTimes.Count > 0)
                    avgMin = withTimes.Average(x => (x.DeliveredAtUtc!.Value - x.DriverConfirmedAtUtc!.Value).TotalMinutes);
                var distKm = g.Sum(x => Math.Max(0.0, x.DistanceKm));
                return new { driverId = g.Key, deliveredCount = g.Count(), totalAmount = g.Sum(x => x.Total), avgDeliveryMinutes = avgMin, totalDistanceKm = Math.Round(distKm, 3) };
            })
            .OrderByDescending(x => x.deliveredCount)
            .ThenByDescending(x => x.totalAmount)
            .Take(10)
            .ToList();

        var ids = topDrivers.Select(x => x.driverId).ToList();
        var names = await _db.Drivers.AsNoTracking().Where(d => ids.Contains(d.Id)).Select(d => new { d.Id, d.Name }).ToListAsync();
        var map = names.ToDictionary(x => x.Id, x => x.Name);
        var topDriversNamed = topDrivers.Select(x => new { x.driverId, driverName = map.TryGetValue(x.driverId, out var n) ? n : $"#{x.driverId}", x.deliveredCount, x.totalAmount, x.avgDeliveryMinutes, x.totalDistanceKm }).ToList();

        return Ok(new { topProducts, topDrivers = topDriversNamed });
    }

    public record AssignDriverReq(int OrderId, int? DriverId);

    // Bulk assign: assign many orders to the same driver in one request.
    public record AssignDriverBulkReq(List<int> OrderIds, int DriverId);

    [HttpPost("assign-driver")]
    public async Task<IActionResult> AssignDriver(AssignDriverReq req)
    {
        var o = await _db.Orders.FirstOrDefaultAsync(x => x.Id == req.OrderId);
        if (o == null) return NotFound(new { error = "not_found" });

        // Prevent assigning if already delivered/cancelled
        if (o.CurrentStatus == OrderStatus.Delivered || o.CurrentStatus == OrderStatus.Cancelled)
            return BadRequest(new { error = "invalid_status" });

        // Unassign allowed
        o.DriverId = req.DriverId;
        if (req.DriverId != null)
        {
            // Allow multi-orders per driver (max 15 active)
            const int maxActiveOrdersPerDriver = 15;
            var activeCount = await _db.Orders.AsNoTracking().CountAsync(x =>
                x.DriverId == req.DriverId &&
                x.Id != o.Id &&
                x.CurrentStatus != OrderStatus.Delivered &&
                x.CurrentStatus != OrderStatus.Cancelled);
            if (activeCount >= maxActiveOrdersPerDriver)
                return BadRequest(new { error = "driver_active_limit" });

            var driver = await _db.Drivers.AsNoTracking().FirstOrDefaultAsync(d => d.Id == req.DriverId);
            var driverName = driver?.Name ?? $"#{req.DriverId}";

            o.CurrentStatus = OrderStatus.ReadyForPickup;
            _db.OrderStatusHistory.Add(new OrderStatusHistory { OrderId = o.Id, Status = o.CurrentStatus, Comment = $"تم تعيين السائق: {driverName}", ChangedByType = "admin" });
            await _notifyHub.Clients.Group($"driver-{req.DriverId}").SendAsync("order_assigned", new { orderId = o.Id });

            // Driver push: only to assigned driver
            await _fcm.SendToUserAsync(DeviceUserType.Driver, req.DriverId.Value,
                "مهمة توصيل",
                "وصلتك مهمة توصيل جديدة",
                new Dictionary<string, string> { ["orderId"] = o.Id.ToString() });

            await _notifications.CreateAndBroadcastAsync(NotificationUserType.Admin, null,
                "تم تعيين سائق", $"تم تعيين السائق {driverName} للطلب #{o.Id}", o.Id);
        }

        await _db.SaveChangesAsync();
        await _notifyHub.Clients.Group("admin").SendAsync("order_assigned", new { orderId = o.Id, driverId = o.DriverId });
        await _notifyHub.Clients.Group($"customer-{o.CustomerId}").SendAsync("order_status", new { orderId = o.Id, status = o.CurrentStatus, driverId = o.DriverId });
        var payload = new { ok = true, orderId = o.Id, status = o.CurrentStatus, driverId = o.DriverId };
        return Ok(payload);
    }

    /// <summary>
    /// Admin cancellation (إلغاء من الإدارة): visible to customer and reflected in order status/history.
    /// </summary>
    [HttpPost("order/{id:int}/cancel")]
    public async Task<IActionResult> AdminCancelOrder(int id)
    {
        var o = await _db.Orders
            .Include(x => x.StatusHistory)
            .FirstOrDefaultAsync(x => x.Id == id);

        if (o == null) return NotFound(new { error = "not_found" });
        if (o.CurrentStatus == OrderStatus.Delivered || o.CurrentStatus == OrderStatus.Cancelled)
            return BadRequest(new { error = "cannot_cancel", message = "لا يمكن إلغاء هذا الطلب" });

        o.CurrentStatus = OrderStatus.Cancelled;

        // Short reason snapshot (used by some UIs)
        var customerText = "تم إلغاء طلبك من قبل إدارة المطعم";
        o.CancelReasonCode = customerText.Length <= 80 ? customerText : customerText[..80];

        _db.OrderStatusHistory.Add(new OrderStatusHistory
        {
            OrderId = o.Id,
            Status = OrderStatus.Cancelled,
            ReasonCode = "admin_cancel",
            Comment = "تم إلغاء الطلب من قبل الإدارة",
            ChangedByType = "admin",
            ChangedAtUtc = DateTime.UtcNow
        });

        // If a driver was assigned, free them.
        if (o.DriverId.HasValue)
        {
            var d = await _db.Drivers.FindAsync(o.DriverId.Value);
            if (d != null) d.Status = DriverStatus.Available;
        }

        await _db.SaveChangesAsync();

        var payload = new { orderId = o.Id, status = o.CurrentStatus, driverId = o.DriverId };
        await _notifyHub.Clients.Group("admin").SendAsync("order_status", payload);
        await _notifyHub.Clients.Group($"customer-{o.CustomerId}").SendAsync("order_status", payload);
        await _notifyHub.Clients.Group("admin").SendAsync("order_status_changed", payload);
        await _notifyHub.Clients.Group($"customer-{o.CustomerId}").SendAsync("order_status_changed", payload);
        if (o.DriverId != null)
            await _notifyHub.Clients.Group($"driver-{o.DriverId}").SendAsync("order_status", payload);

        // Admin notification + push (FCM topic admin/admins)
        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Admin, null,
            "إلغاء طلب", $"تم إلغاء الطلب #{o.Id} من قبل الإدارة", o.Id);

        // Customer in-app notification (no push from here)
        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Customer, o.CustomerId,
            "تم إلغاء طلبك", customerText, o.Id);

        // Customer push (allowed by current rules)
        await _notifications.SendCustomerOrderStatusPushIfNeededAsync(o.CustomerId, o.Id, o.CurrentStatus, o.PrepEtaMinutes, o.DeliveryEtaMinutes);

        return Ok(new { ok = true });
    }

    /// <summary>
    /// Delete order completely (حذف الطلب نهائياً)
    /// </summary>
    [HttpDelete("order/{id:int}/delete")]
    public async Task<IActionResult> DeleteOrder(int id)
    {
        var o = await _db.Orders
            .Include(x => x.Items)
            .Include(x => x.StatusHistory)
            .FirstOrDefaultAsync(x => x.Id == id);

        if (o == null) return NotFound(new { error = "not_found" });

        // Delete order items
        _db.OrderItems.RemoveRange(o.Items);
        
        // Delete order status history
        _db.OrderStatusHistory.RemoveRange(o.StatusHistory);
        
        // Delete order rating if exists
        var rating = await _db.OrderRatings.FirstOrDefaultAsync(r => r.OrderId == id);
        if (rating != null)
            _db.OrderRatings.Remove(rating);
        
        // Delete order complaints/chats if exists
        var complaintThreads = await _db.ComplaintThreads.Where(c => c.OrderId == id).ToListAsync();
        if (complaintThreads.Any())
        {
            foreach (var thread in complaintThreads)
            {
                var messages = await _db.ComplaintMessages.Where(m => m.ThreadId == thread.Id).ToListAsync();
                _db.ComplaintMessages.RemoveRange(messages);
            }
            _db.ComplaintThreads.RemoveRange(complaintThreads);
        }
        
        // Delete the order itself
        _db.Orders.Remove(o);

        // If a driver was assigned, free them
        if (o.DriverId.HasValue)
        {
            var d = await _db.Drivers.FindAsync(o.DriverId.Value);
            if (d != null && d.Status == DriverStatus.Busy)
            {
                // Check if driver has other active orders
                var hasOtherOrders = await _db.Orders
                    .AnyAsync(x => x.DriverId == o.DriverId.Value && 
                                   x.Id != id && 
                                   x.CurrentStatus != OrderStatus.Delivered && 
                                   x.CurrentStatus != OrderStatus.Cancelled);
                if (!hasOtherOrders)
                    d.Status = DriverStatus.Available;
            }
        }

        await _db.SaveChangesAsync();

        // Notify admin clients
        await _notifyHub.Clients.Group("admin").SendAsync("order_deleted", new { orderId = id });

        return Ok(new { ok = true });
    }

    /// <summary>
    /// Delete all orders completely (حذف جميع الطلبات نهائياً)
    /// </summary>
    [HttpDelete("orders/delete-all")]
    public async Task<IActionResult> DeleteAllOrders()
    {
        // Delete all complaint messages first
        await _db.Database.ExecuteSqlRawAsync("DELETE FROM ComplaintMessages WHERE ThreadId IN (SELECT Id FROM ComplaintThreads WHERE OrderId IS NOT NULL)");
        
        // Delete all complaint threads related to orders
        await _db.Database.ExecuteSqlRawAsync("DELETE FROM ComplaintThreads WHERE OrderId IS NOT NULL");
        
        // Delete all order ratings
        await _db.Database.ExecuteSqlRawAsync("DELETE FROM OrderRatings");
        
        // Delete all order status history
        await _db.Database.ExecuteSqlRawAsync("DELETE FROM OrderStatusHistory");
        
        // Delete all order items
        await _db.Database.ExecuteSqlRawAsync("DELETE FROM OrderItems");
        
        // Delete all orders
        await _db.Database.ExecuteSqlRawAsync("DELETE FROM Orders");

        // Free all busy drivers
        var busyDrivers = await _db.Drivers.Where(d => d.Status == DriverStatus.Busy).ToListAsync();
        foreach (var driver in busyDrivers)
        {
            driver.Status = DriverStatus.Available;
        }

        await _db.SaveChangesAsync();

        // Notify admin clients
        await _notifyHub.Clients.Group("admin").SendAsync("orders_deleted_all", new { });

        return Ok(new { ok = true });
    }

    [HttpPost("assign-driver/bulk")]
    public async Task<IActionResult> AssignDriverBulk(AssignDriverBulkReq req)
    {
        if (req.OrderIds == null || req.OrderIds.Count == 0)
            return BadRequest(new { error = "empty" });

        var driver = await _db.Drivers.AsNoTracking().FirstOrDefaultAsync(d => d.Id == req.DriverId);
        if (driver == null) return BadRequest(new { error = "invalid_driver" });

        var driverName = driver.Name ?? $"#{req.DriverId}";

        var distinct = req.OrderIds.Distinct().ToList();
        const int maxActiveOrdersPerDriver = 15;
        var activeCount = await _db.Orders.AsNoTracking().CountAsync(x =>
            x.DriverId == req.DriverId &&
            x.CurrentStatus != OrderStatus.Delivered &&
            x.CurrentStatus != OrderStatus.Cancelled);

        if (activeCount + distinct.Count > maxActiveOrdersPerDriver)
            return BadRequest(new { error = "driver_active_limit" });

        var orders = await _db.Orders.Where(o => distinct.Contains(o.Id)).ToListAsync();
        if (orders.Count == 0) return NotFound(new { error = "not_found" });

        var assignedCount = 0;
        foreach (var o in orders)
        {
            if (o.CurrentStatus == OrderStatus.Delivered || o.CurrentStatus == OrderStatus.Cancelled) continue;
            o.DriverId = req.DriverId;
            o.CurrentStatus = OrderStatus.ReadyForPickup;
            _db.OrderStatusHistory.Add(new OrderStatusHistory { OrderId = o.Id, Status = o.CurrentStatus, Comment = $"تم تعيين السائق (دفعة واحدة): {driverName}", ChangedByType = "admin" });
            await _notifyHub.Clients.Group($"driver-{req.DriverId}").SendAsync("order_assigned", new { orderId = o.Id });
            await _notifyHub.Clients.Group($"customer-{o.CustomerId}").SendAsync("order_status", new { orderId = o.Id, status = o.CurrentStatus, driverId = o.DriverId });
            await _notifications.CreateAndBroadcastAsync(NotificationUserType.Admin, null,
                "تم تعيين سائق", $"تم تعيين السائق {driverName} للطلب #{o.Id}", o.Id);
            assignedCount++;
        }

        await _db.SaveChangesAsync();

        // Push one message to driver (summary)
        await _fcm.SendToUserAsync(DeviceUserType.Driver, req.DriverId,
            "مهام توصيل", $"تم إسناد {assignedCount} طلب/طلبات لك", new Dictionary<string, string> { ["bulk"] = "1" });

        await _notifyHub.Clients.Group("admin").SendAsync("order_assigned", new { bulk = true, driverId = req.DriverId });
        return Ok(new { ok = true, assigned = assignedCount });
    }

    public record UpdateOrderStatusReq(int OrderId, OrderStatus Status, string? Comment);
    
    public record ManualOrderItemReq(int ProductId, int Quantity, string? OptionsSnapshot);

    public record ManualOrderRequest(
        string CustomerName,
        string CustomerPhone,
        string? DeliveryAddress,
        decimal DeliveryFee,
        string? Notes,
        List<ManualOrderItemReq> Items
    );

    [HttpPost("manual-order")]
    public async Task<IActionResult> CreateManualOrder(ManualOrderRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.CustomerName))
            return BadRequest(new { message = "يرجى إدخال اسم الزبون" });

        if (string.IsNullOrWhiteSpace(req.CustomerPhone))
            return BadRequest(new { message = "يرجى إدخال رقم هاتف الزبون" });

        if (req.Items == null || req.Items.Count == 0)
            return BadRequest(new { message = "يرجى إضافة صنف واحد على الأقل" });

        var customer = await _db.Customers
            .FirstOrDefaultAsync(c => c.Phone == req.CustomerPhone);

        if (customer == null)
        {
            customer = new Entities.Customer
            {
                Name = req.CustomerName,
                Phone = req.CustomerPhone,
                DefaultAddress = req.DeliveryAddress ?? "",
            };
            _db.Customers.Add(customer);
            await _db.SaveChangesAsync();
        }

        var productIds = req.Items.Where(i => i.ProductId > 0).Select(i => i.ProductId).Distinct().ToList();
        var offerIds = req.Items.Where(i => i.ProductId < 0).Select(i => Math.Abs(i.ProductId)).Distinct().ToList();

        var products = (productIds.Count == 0)
            ? new List<Product>()
            : await _db.Products.Where(p => productIds.Contains(p.Id) && p.IsActive).ToListAsync();
        if (products.Count != productIds.Count)
            return BadRequest(new { message = "بعض الأصناف غير موجودة أو غير نشطة" });

        var offers = (offerIds.Count == 0)
            ? new List<Offer>()
            : await _db.Offers.AsNoTracking().Where(o => offerIds.Contains(o.Id) && o.IsActive).ToListAsync();
        if (offers.Count != offerIds.Count)
            return BadRequest(new { message = "بعض العروض غير موجودة أو غير نشطة" });

        var offerPrimaryProductId = new Dictionary<int, int>();
        if (offerIds.Count > 0)
        {
            var offerProductLinks = await _db.OfferProducts.AsNoTracking()
                .Where(op => offerIds.Contains(op.OfferId))
                .ToListAsync();
            foreach (var g in offerProductLinks.GroupBy(x => x.OfferId))
                offerPrimaryProductId[g.Key] = g.Select(x => x.ProductId).FirstOrDefault();
        }

        var templateProductIds = productIds.Union(offerPrimaryProductId.Values.Where(pid => pid > 0)).Distinct().ToList();
        var variants = (templateProductIds.Count == 0)
            ? new List<ProductVariant>()
            : await _db.ProductVariants.AsNoTracking()
                .Where(v => templateProductIds.Contains(v.ProductId) && v.IsActive)
                .ToListAsync();

        var addons = (templateProductIds.Count == 0)
            ? new List<ProductAddon>()
            : await _db.ProductAddons.AsNoTracking()
                .Where(a => templateProductIds.Contains(a.ProductId) && a.IsActive)
                .ToListAsync();

        var orderItems = new List<Entities.OrderItem>();
        decimal subtotal = 0;

        foreach (var item in req.Items)
        {
            if (item.Quantity <= 0) continue;

            if (item.ProductId < 0)
            {
                var offerId = Math.Abs(item.ProductId);
                var off = offers.FirstOrDefault(o => o.Id == offerId);
                if (off == null) continue;

                int? variantId = null;
                List<int> addonIds = new();
                if (!string.IsNullOrWhiteSpace(item.OptionsSnapshot))
                {
                    try
                    {
                        using var doc = JsonDocument.Parse(item.OptionsSnapshot);
                        var root = doc.RootElement;
                        if (root.TryGetProperty("variantId", out var v1) && v1.ValueKind == JsonValueKind.Number) variantId = v1.GetInt32();
                        else if (root.TryGetProperty("VariantId", out var v2) && v2.ValueKind == JsonValueKind.Number) variantId = v2.GetInt32();
                        if (root.TryGetProperty("addonIds", out var a1) && a1.ValueKind == JsonValueKind.Array)
                            addonIds = a1.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.Number).Select(x => x.GetInt32()).ToList();
                        else if (root.TryGetProperty("AddonIds", out var a2) && a2.ValueKind == JsonValueKind.Array)
                            addonIds = a2.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.Number).Select(x => x.GetInt32()).ToList();
                    }
                    catch { /* ignore */ }
                }

                decimal variantDelta = 0;
                string? variantName = null;
                decimal addonsDelta = 0;
                var chosenAddons = new List<object>();
                var templateProductId = offerPrimaryProductId.TryGetValue(offerId, out var tpid) ? tpid : 0;
                if (templateProductId > 0)
                {
                    if (variantId.HasValue)
                    {
                        var v = variants.FirstOrDefault(x => x.Id == variantId.Value && x.ProductId == templateProductId && x.IsActive);
                        if (v != null) { variantDelta = v.PriceDelta; variantName = v.Name; }
                    }
                    foreach (var aid in addonIds.Distinct())
                    {
                        var a = addons.FirstOrDefault(x => x.Id == aid && x.ProductId == templateProductId && x.IsActive);
                        if (a != null) { addonsDelta += a.Price; chosenAddons.Add(new { a.Id, a.Name, a.Price }); }
                    }
                }

                var unitPrice = (off.PriceAfter ?? off.PriceBefore ?? 0m) + variantDelta + addonsDelta;
                subtotal += unitPrice * item.Quantity;
                var offerSnap = JsonSerializer.Serialize(new
                {
                    isOffer = true,
                    offerId,
                    variantId,
                    variantName,
                    variantDelta,
                    addonIds = addonIds.Distinct().ToList(),
                    addons = chosenAddons
                });
                orderItems.Add(new Entities.OrderItem
                {
                    ProductId = -offerId,
                    ProductNameSnapshot = off.Title,
                    UnitPriceSnapshot = unitPrice,
                    Quantity = item.Quantity,
                    OptionsSnapshot = offerSnap
                });
                continue;
            }

            if (item.ProductId <= 0) continue;

            var prod = products.First(p => p.Id == item.ProductId);

            int? prodVariantId = null;
            List<int> prodAddonIds = new();
            string? noteText = null;

            if (!string.IsNullOrWhiteSpace(item.OptionsSnapshot))
            {
                try
                {
                    using var doc = JsonDocument.Parse(item.OptionsSnapshot);
                    var root = doc.RootElement;

                    if (root.TryGetProperty("variantId", out var v1) && v1.ValueKind == JsonValueKind.Number) prodVariantId = v1.GetInt32();
                    else if (root.TryGetProperty("VariantId", out var v2) && v2.ValueKind == JsonValueKind.Number) prodVariantId = v2.GetInt32();

                    if (root.TryGetProperty("addonIds", out var a1) && a1.ValueKind == JsonValueKind.Array)
                        prodAddonIds = a1.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.Number).Select(x => x.GetInt32()).ToList();
                    else if (root.TryGetProperty("AddonIds", out var a2) && a2.ValueKind == JsonValueKind.Array)
                        prodAddonIds = a2.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.Number).Select(x => x.GetInt32()).ToList();

                    if (root.TryGetProperty("note", out var n1) && n1.ValueKind == JsonValueKind.String) noteText = n1.GetString();
                    else if (root.TryGetProperty("Note", out var n2) && n2.ValueKind == JsonValueKind.String) noteText = n2.GetString();
                }
                catch
                {
                    // ignore invalid snapshot
                }
            }

            decimal prodVariantDelta = 0;
            string? prodVariantName = null;
            if (prodVariantId.HasValue)
            {
                var v = variants.FirstOrDefault(x => x.Id == prodVariantId.Value && x.ProductId == prod.Id && x.IsActive);
                if (v != null)
                {
                    prodVariantDelta = v.PriceDelta;
                    prodVariantName = v.Name;
                }
            }

            decimal prodAddonsDelta = 0;
            var prodChosenAddons = new List<object>();
            foreach (var aid in prodAddonIds.Distinct())
            {
                var a = addons.FirstOrDefault(x => x.Id == aid && x.ProductId == prod.Id && x.IsActive);
                if (a == null) continue;
                prodAddonsDelta += a.Price;
                prodChosenAddons.Add(new { a.Id, a.Name, a.Price });
            }

            var prodUnitPrice = prod.Price + prodVariantDelta + prodAddonsDelta;
            subtotal += prodUnitPrice * item.Quantity;

            var snap = JsonSerializer.Serialize(new
            {
                variantId = prodVariantId,
                variantName = prodVariantName,
                variantDelta = prodVariantDelta,
                addonIds = prodAddonIds.Distinct().ToList(),
                addons = prodChosenAddons,
                note = noteText
            });

            orderItems.Add(new Entities.OrderItem
            {
                ProductId = prod.Id,
                ProductNameSnapshot = prod.Name,
                UnitPriceSnapshot = prodUnitPrice,
                Quantity = item.Quantity,
                OptionsSnapshot = snap
            });
        }

        var deliveryFee = req.DeliveryFee > 0 ? req.DeliveryFee : 0m;
        var total = subtotal + deliveryFee;

        var order = new Entities.Order
        {
            CustomerId = customer.Id,
            CurrentStatus = Entities.OrderStatus.New,
            DeliveryAddress = req.DeliveryAddress ?? "",
            DeliveryLat = 0,
            DeliveryLng = 0,
            OrderType = "pickup",
            Notes = req.Notes ?? "",
            Subtotal = subtotal,
            DeliveryFee = deliveryFee,
            TotalBeforeDiscount = total,
            CartDiscount = 0,
            Total = total,
            IdempotencyKey = Guid.NewGuid().ToString(),
            Items = orderItems,
        };

        order.StatusHistory.Add(new Entities.OrderStatusHistory
        {
            Status = Entities.OrderStatus.New,
            ChangedByType = "admin",
            Comment = "طلب يدوي من لوحة التحكم",
        });

        _db.Orders.Add(order);
        await _db.SaveChangesAsync();

        await _notifyHub.Clients.Group("admin").SendAsync("order_new", new { orderId = order.Id });

        return Ok(new { id = order.Id, ok = true });
    }

    public record UpdateOrderEtaReq(int OrderId, int? PrepEtaMinutes, int? DeliveryEtaMinutes);

    [HttpPost("order-eta")]
    public async Task<IActionResult> UpdateOrderEta(UpdateOrderEtaReq req)
    {
        var o = await _db.Orders.FirstOrDefaultAsync(x => x.Id == req.OrderId);
        if (o == null) return NotFound(new { error = "not_found" });

        o.PrepEtaMinutes = req.PrepEtaMinutes;
        o.DeliveryEtaMinutes = req.DeliveryEtaMinutes;

        // If both provided, compute expected delivery time.
        var totalMinutes = (req.PrepEtaMinutes ?? 0) + (req.DeliveryEtaMinutes ?? 0);
        if (totalMinutes > 0)
            o.ExpectedDeliveryAtUtc = DateTime.UtcNow.AddMinutes(totalMinutes);
        else
            o.ExpectedDeliveryAtUtc = null;

        o.LastEtaUpdatedAtUtc = DateTime.UtcNow;
        _db.OrderStatusHistory.Add(new OrderStatusHistory
        {
            OrderId = o.Id,
            Status = o.CurrentStatus,
            ChangedByType = "admin",
            Comment = $"تم تحديث الوقت المتوقع: تحضير={req.PrepEtaMinutes ?? 0}د، توصيل={req.DeliveryEtaMinutes ?? 0}د"
        });

        await _db.SaveChangesAsync();

        await _notifyHub.Clients.Group("admin").SendAsync("eta_badge", new { orderId = o.Id });
        // In-app notifications + push (FCM) for customer
        var prep = req.PrepEtaMinutes ?? 0;
        var del = req.DeliveryEtaMinutes ?? 0;
        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Admin, null,
            "تحديث الوقت المتوقع", $"تم تحديث ETA للطلب #{o.Id}", o.Id);
        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Customer, o.CustomerId,
            "تحديث الوقت المتوقع", $"تم تحديد الوقت المتوقع ✅ (تحضير: {prep} د، توصيل: {del} د)", o.Id);
        if (o.DriverId != null)
        {
            await _notifications.CreateAndBroadcastAsync(NotificationUserType.Driver, o.DriverId,
                "تحديث الوقت المتوقع", $"تم تحديث ETA للطلب #{o.Id}", o.Id);
        }
        await _notifications.SendCustomerEtaUpdatedPushAsync(o.CustomerId, o.Id, req.PrepEtaMinutes, req.DeliveryEtaMinutes);

        var payload = new
        {
            orderId = o.Id,
            prepEtaMinutes = o.PrepEtaMinutes,
            deliveryEtaMinutes = o.DeliveryEtaMinutes,
            expectedDeliveryAtUtc = o.ExpectedDeliveryAtUtc,
            lastEtaUpdatedAtUtc = o.LastEtaUpdatedAtUtc
        };

        await _notifyHub.Clients.Group("admin").SendAsync("order_eta", payload);
        await _notifyHub.Clients.Group($"customer-{o.CustomerId}").SendAsync("order_eta", payload);
        if (o.DriverId != null)
            await _notifyHub.Clients.Group($"driver-{o.DriverId}").SendAsync("order_eta", payload);

        return Ok(payload);
    }

    [HttpPost("order-status")]
    public async Task<IActionResult> UpdateOrderStatus(UpdateOrderStatusReq req)
    {
        var o = await _db.Orders.FirstOrDefaultAsync(x => x.Id == req.OrderId);
        if (o == null) return NotFound(new { error = "not_found" });
        if (o.CurrentStatus == OrderStatus.Delivered || o.CurrentStatus == OrderStatus.Cancelled)
            return BadRequest(new { error = "final_status" });

        var previous = o.CurrentStatus;
        o.CurrentStatus = req.Status;

        // IMPORTANT for reports: ensure DeliveredAtUtc is set when admin marks an order as Delivered.
        if (req.Status == OrderStatus.Delivered && o.DeliveredAtUtc == null)
            o.DeliveredAtUtc = DateTime.UtcNow;

        // Helpful for tracking/ETA flows if admin assigns "WithDriver"
        if (req.Status == OrderStatus.WithDriver && o.DriverConfirmedAtUtc == null)
            o.DriverConfirmedAtUtc = DateTime.UtcNow;

        _db.OrderStatusHistory.Add(new OrderStatusHistory
        {
            OrderId = o.Id,
            Status = req.Status,
            Comment = string.IsNullOrWhiteSpace(req.Comment)
                ? (previous == req.Status ? null : $"{previous} -> {req.Status}")
                : req.Comment,
            ChangedByType = "admin"
        });
        await _db.SaveChangesAsync();
        var payload = new { orderId = o.Id, status = o.CurrentStatus, driverId = o.DriverId };
        await _notifyHub.Clients.Group("admin").SendAsync("order_status", payload);
        await _notifyHub.Clients.Group($"customer-{o.CustomerId}").SendAsync("order_status", payload);
        // Required unified event name
        await _notifyHub.Clients.Group("admin").SendAsync("order_status_changed", payload);
        await _notifyHub.Clients.Group($"customer-{o.CustomerId}").SendAsync("order_status_changed", payload);

        var statusArabic = o.CurrentStatus switch
        {
            OrderStatus.New => "جديد",
            OrderStatus.Confirmed => "مؤكد",
            OrderStatus.Preparing => "قيد التحضير",
            OrderStatus.ReadyForPickup => "جاهز للاستلام",
            OrderStatus.WithDriver => "مع السائق",
            OrderStatus.Delivered => "تم التسليم",
            OrderStatus.Cancelled => "ملغي",
            OrderStatus.Accepted => "مقبول",
            _ => o.CurrentStatus.ToString()
        };
        
        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Admin, null,
            "تحديث حالة", $"تم تحديث حالة الطلب #{o.Id} إلى {statusArabic}", o.Id);

        // Customer push: 3 notifications only
        await _notifications.SendCustomerOrderStatusPushIfNeededAsync(o.CustomerId, o.Id, o.CurrentStatus, o.PrepEtaMinutes, o.DeliveryEtaMinutes);
        return Ok(payload);
    }

    /// <summary>
    /// تعليم طلب "استلام من الفرع" كمسلَّم (ينتقل إلى الطلبات المسلَّمة والتقارير).
    /// يعمل فقط للطلبات غير المسلَّمة/غير الملغاة والتي لا تحتوي على إحداثيات توصيل (0,0).
    /// </summary>
    [HttpPost("orders/{id:int}/mark-picked-up")]
    public async Task<IActionResult> MarkPickupOrderDelivered(int id)
    {
        var o = await _db.Orders.FirstOrDefaultAsync(x => x.Id == id);
        if (o == null) return NotFound(new { error = "not_found" });
        if (o.CurrentStatus == OrderStatus.Delivered || o.CurrentStatus == OrderStatus.Cancelled)
            return BadRequest(new { error = "final_status" });

        // اعتبر الطلب استلام من الفرع عندما لا يوجد إحداثيات توصيل (0,0)
        var isPickup = o.DeliveryLat == 0 && o.DeliveryLng == 0;
        if (!isPickup)
            return BadRequest(new { error = "not_pickup", message = "هذا الطلب ليس استلاماً من الفرع" });

        var previous = o.CurrentStatus;
        o.CurrentStatus = OrderStatus.Delivered;
        if (o.DeliveredAtUtc == null)
            o.DeliveredAtUtc = DateTime.UtcNow;

        _db.OrderStatusHistory.Add(new OrderStatusHistory
        {
            OrderId = o.Id,
            Status = OrderStatus.Delivered,
            Comment = "تم الاستلام من الفرع (من لوحة التحكم)",
            ChangedByType = "admin"
        });
        await _db.SaveChangesAsync();

        var payload = new { orderId = o.Id, status = o.CurrentStatus, driverId = o.DriverId };
        await _notifyHub.Clients.Group("admin").SendAsync("order_status", payload);
        await _notifyHub.Clients.Group($"customer-{o.CustomerId}").SendAsync("order_status", payload);
        await _notifyHub.Clients.Group("admin").SendAsync("order_status_changed", payload);
        await _notifyHub.Clients.Group($"customer-{o.CustomerId}").SendAsync("order_status_changed", payload);

        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Admin, null,
            "تحديث حالة", $"تم تعليم الطلب #{o.Id} كمستلم من الفرع", o.Id);
        await _notifications.SendCustomerOrderStatusPushIfNeededAsync(o.CustomerId, o.Id, o.CurrentStatus, o.PrepEtaMinutes, o.DeliveryEtaMinutes);

        return Ok(payload);
    }

    [HttpGet("complaints")]
    public async Task<IActionResult> ListComplaints()
    {
        var threads = await _db.ComplaintThreads.AsNoTracking()
            .Select(t => new
            {
                t.Id,
                t.Title,
                t.CustomerId,
                t.OrderId,
                t.CreatedAtUtc,
                t.UpdatedAtUtc,
                t.LastAdminSeenAtUtc,
                customerName = _db.Customers.Where(c => c.Id == t.CustomerId).Select(c => c.Name).FirstOrDefault(),
                customerPhone = _db.Customers.Where(c => c.Id == t.CustomerId).Select(c => c.Phone).FirstOrDefault(),
                isChatBlocked = _db.Customers.Where(c => c.Id == t.CustomerId).Select(c => c.IsChatBlocked).FirstOrDefault(),
                lastMsg = _db.ComplaintMessages
                    .Where(m => m.ThreadId == t.Id)
                    .OrderByDescending(m => m.CreatedAtUtc)
                    .Select(m => new { m.FromAdmin, m.Message, m.CreatedAtUtc })
                    .FirstOrDefault(),
                unreadCount = _db.ComplaintMessages
                    .Where(m => m.ThreadId == t.Id && !m.FromAdmin && (t.LastAdminSeenAtUtc == null || m.CreatedAtUtc > t.LastAdminSeenAtUtc))
                    .Count()
            })
            .OrderByDescending(x => x.lastMsg != null ? x.lastMsg.CreatedAtUtc : x.UpdatedAtUtc)
            .ToListAsync();

        var list = threads.Select(x => new
        {
            x.Id,
            x.Title,
            x.CustomerId,
            customerName = x.customerName ?? "",
            customerPhone = x.customerPhone ?? "",
            isChatBlocked = x.isChatBlocked,
            x.OrderId,
            x.CreatedAtUtc,
            x.UpdatedAtUtc,
            unreadCount = x.unreadCount,
            lastMessagePreview = x.lastMsg == null ? "" : (x.lastMsg.FromAdmin ? "الإدارة: " : "الزبون: ") + (x.lastMsg.Message.Length > 60 ? x.lastMsg.Message.Substring(0, 60) + "…" : x.lastMsg.Message),
            lastMessageAtUtc = x.lastMsg?.CreatedAtUtc
        }).ToList();

        return Ok(list);
    }

    [HttpGet("complaint/{threadId:int}")]
    public async Task<IActionResult> GetComplaintThread(int threadId)
    {
        var t = await _db.ComplaintThreads
            .Include(x => x.Messages)
            .FirstOrDefaultAsync(x => x.Id == threadId);
        if (t == null) return NotFound(new { error = "not_found" });

        var customer = await _db.Customers.AsNoTracking().FirstOrDefaultAsync(c => c.Id == t.CustomerId);

        // mark as read for admin
        t.LastAdminSeenAtUtc = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(new
        {
            t.Id,
            t.Title,
            t.OrderId,
            t.CustomerId,
            customerName = customer?.Name ?? "",
            customerPhone = customer?.Phone ?? "",
            isChatBlocked = customer?.IsChatBlocked == true,
            messages = t.Messages.OrderBy(m => m.CreatedAtUtc)
                .Select(m => new { m.Id, fromAdmin = m.FromAdmin, message = m.Message, m.CreatedAtUtc })
        });
    }

    public record AdminReplyReq(string Message);

    [HttpPost("complaint/{threadId:int}/reply")]
    public async Task<IActionResult> ReplyComplaint(int threadId, AdminReplyReq req)
    {
        var t = await _db.ComplaintThreads.FirstOrDefaultAsync(x => x.Id == threadId);
        if (t == null) return NotFound(new { error = "not_found" });
        var now = DateTime.UtcNow;
        var msg = new ComplaintMessage { ThreadId = t.Id, FromAdmin = true, Message = req.Message };
        _db.ComplaintMessages.Add(msg);
        t.UpdatedAtUtc = now;
        await _db.SaveChangesAsync();

        var payload = new { id = msg.Id, threadId = t.Id, fromAdmin = true, message = req.Message, createdAtUtc = msg.CreatedAtUtc };        // Required unified event name
        await _notifyHub.Clients.Group($"customer-{t.CustomerId}").SendAsync("chat_message_received", payload);
        await _notifyHub.Clients.Group("admin").SendAsync("chat_message_received", payload);

        // Also create an in-app notification record for the customer (shows in Notifications screen)
        var snippet = (req.Message ?? "").Trim();
        if (snippet.Length > 80) snippet = snippet.Substring(0, 80) + "…";
        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Customer, t.CustomerId,
            "رسالة جديدة", snippet, t.OrderId);

        await _notifications.SendCustomerChatPushAsync(t.CustomerId, t.OrderId, req.Message);

        return Ok(payload);
    }

    public record BulkDeleteComplaintsReq(List<int> ThreadIds);

    /// <summary>
    /// حذف عدة محادثات (شكاوى/دردشة) دفعة واحدة من لوحة التحكم.
    /// </summary>
    [HttpPost("complaints/bulk-delete")]
    public async Task<IActionResult> BulkDeleteComplaints(BulkDeleteComplaintsReq req)
    {
        var ids = (req.ThreadIds ?? new List<int>()).Where(id => id > 0).Distinct().ToList();
        if (ids.Count == 0) return BadRequest(new { error = "no_ids", message = "لم يتم تحديد أي محادثة للحذف" });

        var threads = await _db.ComplaintThreads.Where(t => ids.Contains(t.Id)).ToListAsync();
        if (threads.Count == 0) return Ok(new { deleted = 0 });

        var threadIds = threads.Select(t => t.Id).ToList();
        var msgs = await _db.ComplaintMessages.Where(m => threadIds.Contains(m.ThreadId)).ToListAsync();
        if (msgs.Count > 0)
            _db.ComplaintMessages.RemoveRange(msgs);

        _db.ComplaintThreads.RemoveRange(threads);
        await _db.SaveChangesAsync();

        return Ok(new { deleted = threads.Count });
    }

    /// <summary>
    /// إرسال رسالة دردشة لجميع المستخدمين (تظهر في دردشة كل زبون + إشعار FCM).
    /// </summary>
    public record BroadcastChatReq(string Message);

    [HttpPost("broadcast-chat")]
    public async Task<IActionResult> BroadcastChat(BroadcastChatReq req)
    {
        var message = (req.Message ?? "").Trim();
        if (string.IsNullOrEmpty(message)) return BadRequest(new { error = "message_required" });

        var now = DateTime.UtcNow;
        var customerIds = await _db.Customers.Select(c => c.Id).ToListAsync();
        if (customerIds.Count == 0) return Ok(new { sent = 0, message = "لا يوجد زبائن" });

        var existingThreads = await _db.ComplaintThreads
            .Where(t => customerIds.Contains(t.CustomerId))
            .ToDictionaryAsync(t => t.CustomerId, t => t);

        foreach (var cid in customerIds)
        {
            if (!existingThreads.TryGetValue(cid, out var thread))
            {
                thread = new ComplaintThread
                {
                    CustomerId = cid,
                    OrderId = null,
                    Title = "دردشة مع المطعم",
                    UpdatedAtUtc = now,
                    CreatedAtUtc = now,
                    LastAdminSeenAtUtc = now
                };
                _db.ComplaintThreads.Add(thread);
                existingThreads[cid] = thread;
            }
        }
        await _db.SaveChangesAsync();

        foreach (var cid in customerIds)
        {
            var thread = existingThreads[cid];
            _db.ComplaintMessages.Add(new ComplaintMessage { ThreadId = thread.Id, FromAdmin = true, Message = message, CreatedAtUtc = now });
        }
        await _db.SaveChangesAsync();

        foreach (var cid in customerIds)
        {
            var thread = existingThreads[cid];
            var payload = new { id = 0, threadId = thread.Id, fromAdmin = true, message, createdAtUtc = now };
            await _notifyHub.Clients.Group($"customer-{cid}").SendAsync("chat_message_received", payload);
        }
        await _notifyHub.Clients.Group("admin").SendAsync("chat_message_received", new { broadcast = true, count = customerIds.Count });

        var snippet = message.Length > 80 ? message.Substring(0, 80) + "…" : message;
        await _fcm.SendToTopicAsync("customers", "رسالة من المطعم", snippet, new Dictionary<string, string> { ["type"] = "chat" });

        return Ok(new { sent = customerIds.Count });
    }

    [HttpGet("settings")]
    public async Task<IActionResult> GetSettings()
    {
        var s = await _db.RestaurantSettings.FirstAsync();

        // IMPORTANT: Admin Settings page expects camelCase fields.
        // Returning the EF entity directly breaks the UI (undefined fields) even if the API is 200.
        return Ok(new
        {
            restaurantName = s.RestaurantName,
            logoUrl = s.LogoUrl,
            customerSplashUrl = s.CustomerSplashUrl,
            driverSplashUrl = s.DriverSplashUrl,
            splashBackground1Url = s.SplashBackground1Url,
            splashBackground2Url = s.SplashBackground2Url,
            primaryColorHex = s.PrimaryColorHex,
            secondaryColorHex = s.SecondaryColorHex,
            offersColorHex = s.OffersColorHex,
            welcomeText = s.WelcomeText,
            onboardingJson = s.OnboardingJson,
            homeBannersJson = s.HomeBannersJson,
            workHours = s.WorkHours,
            restaurantLat = s.RestaurantLat,
            restaurantLng = s.RestaurantLng,
            minOrderAmount = s.MinOrderAmount,
            deliveryFeeType = (int)s.DeliveryFeeType,
            deliveryFeeValue = s.DeliveryFeeValue,
            deliveryFeePerKm = s.DeliveryFeePerKm,
            freeDeliveryMaxKm = s.FreeDeliveryMaxKm,
            supportPhone = s.SupportPhone,
            supportWhatsApp = s.SupportWhatsApp,
            closedMessage = s.ClosedMessage,
            closedScreenImageUrl = s.ClosedScreenImageUrl,
            isManuallyClosed = s.IsManuallyClosed,
            isAcceptingOrders = s.IsAcceptingOrders,
            routingProfile = s.RoutingProfile,
            driverSpeedBikeKmH = s.DriverSpeedBikeKmH,
            driverSpeedCarKmH = s.DriverSpeedCarKmH,
            facebookUrl = s.FacebookUrl,
            instagramUrl = s.InstagramUrl,
            telegramUrl = s.TelegramUrl,
            updatedAtUtc = s.UpdatedAtUtc
        });
    }

    /// <summary>
    /// Printer assignment: main (full order), sub1/sub2 (per category). Returns settings + categories for the form.
    /// </summary>
    [HttpGet("printers/settings")]
    public async Task<IActionResult> GetPrinterSettings()
    {
        var s = await _db.RestaurantSettings.AsNoTracking().FirstOrDefaultAsync();
        var printerSettings = new
        {
            mainPrinterName = "",
            sub1PrinterName = "",
            sub2PrinterName = "",
            sub1CategoryId = (int?)null,
            sub2CategoryId = (int?)null
        };
        if (!string.IsNullOrWhiteSpace(s?.PrinterSettingsJson))
        {
            try
            {
                using var doc = JsonDocument.Parse(s.PrinterSettingsJson);
                var r = doc.RootElement;
                printerSettings = new
                {
                    mainPrinterName = r.TryGetProperty("mainPrinterName", out var m) ? m.GetString() ?? "" : "",
                    sub1PrinterName = r.TryGetProperty("sub1PrinterName", out var s1) ? s1.GetString() ?? "" : "",
                    sub2PrinterName = r.TryGetProperty("sub2PrinterName", out var s2) ? s2.GetString() ?? "" : "",
                    sub1CategoryId = r.TryGetProperty("sub1CategoryId", out var c1) && c1.ValueKind == JsonValueKind.Number && c1.TryGetInt32(out var v1) ? v1 : (int?)null,
                    sub2CategoryId = r.TryGetProperty("sub2CategoryId", out var c2) && c2.ValueKind == JsonValueKind.Number && c2.TryGetInt32(out var v2) ? v2 : (int?)null
                };
            }
            catch { /* use defaults */ }
        }

        var categories = await _db.Categories.AsNoTracking()
            .OrderBy(c => c.SortOrder)
            .Select(c => new { id = c.Id, name = c.Name })
            .ToListAsync();

        return Ok(new { printerSettings, categories });
    }

    public record SavePrinterSettingsReq(
        string? MainPrinterName,
        string? Sub1PrinterName,
        string? Sub2PrinterName,
        int? Sub1CategoryId,
        int? Sub2CategoryId
    );

    [HttpPost("printers/settings")]
    public async Task<IActionResult> SavePrinterSettings(SavePrinterSettingsReq req)
    {
        var s = await _db.RestaurantSettings.FirstAsync();
        var json = JsonSerializer.Serialize(new
        {
            mainPrinterName = req.MainPrinterName ?? "",
            sub1PrinterName = req.Sub1PrinterName ?? "",
            sub2PrinterName = req.Sub2PrinterName ?? "",
            sub1CategoryId = req.Sub1CategoryId,
            sub2CategoryId = req.Sub2CategoryId
        });
        s.PrinterSettingsJson = json;
        s.UpdatedAtUtc = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return Ok(new { ok = true });
    }

    /// <summary>
    /// Returns which print targets have content for this order: main (always), sub1/sub2 only if order has items in the configured category.
    /// </summary>
    [HttpGet("order/{id:int}/print-targets")]
    public async Task<IActionResult> GetOrderPrintTargets(int id)
    {
        var o = await _db.Orders.AsNoTracking().Include(x => x.Items).FirstOrDefaultAsync(x => x.Id == id);
        if (o == null) return NotFound();

        var productIds = o.Items.Select(x => x.ProductId).Distinct().ToList();
        var productCategoryIds = productIds.Count == 0
            ? new Dictionary<int, int>()
            : await _db.Products.AsNoTracking()
                .Where(p => productIds.Contains(p.Id))
                .Select(p => new { p.Id, p.CategoryId })
                .ToDictionaryAsync(x => x.Id, x => x.CategoryId);

        var orderCategoryIds = o.Items
            .Select(it => productCategoryIds.TryGetValue(it.ProductId, out var cid) ? cid : (int?)null)
            .Where(cid => cid.HasValue)
            .Select(cid => cid!.Value)
            .Distinct()
            .ToHashSet();

        var s = await _db.RestaurantSettings.AsNoTracking().FirstOrDefaultAsync();
        int? sub1Cat = null, sub2Cat = null;
        if (!string.IsNullOrWhiteSpace(s?.PrinterSettingsJson))
        {
            try
            {
                using var doc = JsonDocument.Parse(s.PrinterSettingsJson);
                var r = doc.RootElement;
                if (r.TryGetProperty("sub1CategoryId", out var j1) && j1.ValueKind == JsonValueKind.Number && j1.TryGetInt32(out var c1))
                    sub1Cat = c1;
                if (r.TryGetProperty("sub2CategoryId", out var j2) && j2.ValueKind == JsonValueKind.Number && j2.TryGetInt32(out var c2))
                    sub2Cat = c2;
            }
            catch { /* ignore */ }
        }

        return Ok(new
        {
            main = true,
            sub1 = sub1Cat.HasValue && orderCategoryIds.Contains(sub1Cat.Value),
            sub2 = sub2Cat.HasValue && orderCategoryIds.Contains(sub2Cat.Value)
        });
    }

    [HttpGet("ratings")]
    public async Task<IActionResult> ListRatings()
    {
        var list = await _db.Ratings.AsNoTracking()
            .OrderByDescending(r => r.CreatedAtUtc)
            .Take(500)
            .ToListAsync();

        var orderIds = list.Select(r => r.OrderId).Distinct().ToList();
        var orders = await _db.Orders.AsNoTracking()
            .Where(o => orderIds.Contains(o.Id))
            .Select(o => new { o.Id, o.CustomerId, o.DriverId, o.Total, o.CreatedAtUtc, o.CurrentStatus })
            .ToListAsync();

        var custIds = orders.Select(o => o.CustomerId).Distinct().ToList();
        var customers = await _db.Customers.AsNoTracking()
            .Where(c => custIds.Contains(c.Id))
            .Select(c => new { c.Id, c.Name, c.Phone })
            .ToListAsync();

        var driverIds = orders.Where(o => o.DriverId != null).Select(o => o.DriverId!.Value).Distinct().ToList();
        var drivers = await _db.Drivers.AsNoTracking()
            .Where(d => driverIds.Contains(d.Id))
            .Select(d => new { d.Id, d.Name, d.Phone })
            .ToListAsync();

        var byOrder = orders.ToDictionary(o => o.Id, o => o);
        var byCust = customers.ToDictionary(c => c.Id, c => c);
        var byDrv = drivers.ToDictionary(d => d.Id, d => d);

        var dto = list.Select(r =>
        {
            byOrder.TryGetValue(r.OrderId, out var o);
            byCust.TryGetValue(r.CustomerId, out var c);
            var drvId = (o?.DriverId) ?? (r.DriverId == 0 ? null : r.DriverId);
            if (drvId != null && byDrv.TryGetValue(drvId.Value, out var d))
            {
                return new
                {
                    id = r.Id,
                    orderId = r.OrderId,
                    createdAtUtc = r.CreatedAtUtc,
                    customer = c == null ? null : new { id = c.Id, name = c.Name, phone = c.Phone },
                    // Keep a single anonymous type shape across branches (driver is object?)
                    driver = (object?)new { id = d.Id, name = d.Name, phone = d.Phone },
                    driverStars = r.Stars > 0 ? r.Stars : (int?)null,
                    driverComment = r.Comment,
                    restaurantStars = r.RestaurantStars,
                    restaurantComment = r.RestaurantComment,
                    orderTotal = o?.Total,
                    orderStatus = o?.CurrentStatus.ToString()
                };
            }

            return new
            {
                id = r.Id,
                orderId = r.OrderId,
                createdAtUtc = r.CreatedAtUtc,
                customer = c == null ? null : new { id = c.Id, name = c.Name, phone = c.Phone },
                driver = (object?)null,
                driverStars = r.Stars > 0 ? r.Stars : (int?)null,
                driverComment = r.Comment,
                restaurantStars = r.RestaurantStars,
                restaurantComment = r.RestaurantComment,
                orderTotal = o?.Total,
                orderStatus = o?.CurrentStatus.ToString()
            };
        }).ToList();

        // Simple aggregates for dashboard
        double avgRestaurant = dto.Where(x => x.restaurantStars != null).Select(x => (double)x.restaurantStars!.Value).DefaultIfEmpty(0).Average();
        double avgDriver = dto.Where(x => x.driverStars != null).Select(x => (double)x.driverStars!.Value).DefaultIfEmpty(0).Average();

        return Ok(new
        {
            averages = new
            {
                restaurant = avgRestaurant == 0 ? (double?)null : Math.Round(avgRestaurant, 2),
                driver = avgDriver == 0 ? (double?)null : Math.Round(avgDriver, 2)
            },
            items = dto
        });
    }

    // IMPORTANT: Admin UI should be able to save settings field-by-field (change one field without resubmitting all).
    // Therefore all fields are nullable and we only update what was actually provided.
    public record UpdateSettingsReq(
        string? RestaurantName,
        string? LogoUrl,
        string? ClosedMessage,
        string? ClosedScreenImageUrl,
        string? CustomerSplashUrl,
        string? DriverSplashUrl,
        string? SplashBackground1Url,
        string? SplashBackground2Url,
        string? PrimaryColorHex,
        string? SecondaryColorHex,
        string? OffersColorHex,
        string? WelcomeText,
        string? OnboardingJson,
        string? HomeBannersJson,
        string? WorkHours,
        double? RestaurantLat,
        double? RestaurantLng,
        decimal? MinOrderAmount,
        DeliveryFeeType? DeliveryFeeType,
        decimal? DeliveryFeeValue,
        decimal? DeliveryFeePerKm,
        double? FreeDeliveryMaxKm,
        string? SupportPhone,
        string? SupportWhatsApp,
        string? FacebookUrl,
        string? InstagramUrl,
        string? TelegramUrl,
        bool? IsManuallyClosed,
        bool? IsAcceptingOrders,
        string? RoutingProfile,
        decimal? DriverSpeedBikeKmH,
        decimal? DriverSpeedCarKmH
    );

    [HttpPost("settings")]
    public async Task<IActionResult> UpdateSettings(UpdateSettingsReq req)
    {
        var s = await _db.RestaurantSettings.FirstAsync();

        if (!string.IsNullOrWhiteSpace(req.RestaurantName)) s.RestaurantName = req.RestaurantName!.Trim();
        if (req.LogoUrl != null) s.LogoUrl = req.LogoUrl;
        if (req.ClosedMessage != null) s.ClosedMessage = req.ClosedMessage;
        if (req.ClosedScreenImageUrl != null) s.ClosedScreenImageUrl = req.ClosedScreenImageUrl;
        if (req.CustomerSplashUrl != null) s.CustomerSplashUrl = req.CustomerSplashUrl;
        if (req.DriverSplashUrl != null) s.DriverSplashUrl = req.DriverSplashUrl;
        if (req.SplashBackground1Url != null) s.SplashBackground1Url = req.SplashBackground1Url;
        if (req.SplashBackground2Url != null) s.SplashBackground2Url = req.SplashBackground2Url;
        if (!string.IsNullOrWhiteSpace(req.PrimaryColorHex)) s.PrimaryColorHex = req.PrimaryColorHex!.Trim();
        if (!string.IsNullOrWhiteSpace(req.SecondaryColorHex)) s.SecondaryColorHex = req.SecondaryColorHex!.Trim();
        if (!string.IsNullOrWhiteSpace(req.OffersColorHex)) s.OffersColorHex = req.OffersColorHex!.Trim();
        if (req.WelcomeText != null) s.WelcomeText = req.WelcomeText;
        if (req.OnboardingJson != null) s.OnboardingJson = req.OnboardingJson;
        if (req.HomeBannersJson != null) s.HomeBannersJson = req.HomeBannersJson;
        if (req.WorkHours != null) s.WorkHours = req.WorkHours;
        if (req.RestaurantLat.HasValue) s.RestaurantLat = req.RestaurantLat.Value;
        if (req.RestaurantLng.HasValue) s.RestaurantLng = req.RestaurantLng.Value;
        if (req.MinOrderAmount.HasValue) s.MinOrderAmount = req.MinOrderAmount.Value;
        if (req.DeliveryFeeType.HasValue) s.DeliveryFeeType = req.DeliveryFeeType.Value;
        if (req.DeliveryFeeValue.HasValue) s.DeliveryFeeValue = req.DeliveryFeeValue.Value;
        if (req.DeliveryFeePerKm.HasValue) s.DeliveryFeePerKm = Math.Max(0, req.DeliveryFeePerKm.Value);
        if (req.FreeDeliveryMaxKm.HasValue) s.FreeDeliveryMaxKm = req.FreeDeliveryMaxKm.Value < 0 ? 0 : req.FreeDeliveryMaxKm.Value;
        if (req.SupportPhone != null) s.SupportPhone = req.SupportPhone;
        if (req.SupportWhatsApp != null) s.SupportWhatsApp = req.SupportWhatsApp;
        if (req.FacebookUrl != null) s.FacebookUrl = req.FacebookUrl;
        if (req.InstagramUrl != null) s.InstagramUrl = req.InstagramUrl;
        if (req.TelegramUrl != null) s.TelegramUrl = req.TelegramUrl;
        // Closure logic: apps rely on IsManuallyClosed, while older admin flows used IsAcceptingOrders.
        if (req.IsManuallyClosed.HasValue)
        {
            s.IsManuallyClosed = req.IsManuallyClosed.Value;
            // Keep the other flag coherent unless explicitly overridden.
            if (!req.IsAcceptingOrders.HasValue)
            {
                s.IsAcceptingOrders = !req.IsManuallyClosed.Value;
            }
        }
        if (req.IsAcceptingOrders.HasValue) s.IsAcceptingOrders = req.IsAcceptingOrders.Value;
        if (req.RoutingProfile != null)
        {
            s.RoutingProfile = string.IsNullOrWhiteSpace(req.RoutingProfile) ? "driving" : req.RoutingProfile.Trim();
        }

        if (req.DriverSpeedBikeKmH.HasValue) s.DriverSpeedBikeKmH = Math.Clamp(req.DriverSpeedBikeKmH.Value, 1m, 120m);
        if (req.DriverSpeedCarKmH.HasValue) s.DriverSpeedCarKmH = Math.Clamp(req.DriverSpeedCarKmH.Value, 1m, 160m);

        // Bump settings version for caching.
        s.UpdatedAtUtc = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        var payload = new
        {
            s.RestaurantName,
            s.PrimaryColorHex,
            s.SecondaryColorHex,
            s.OffersColorHex,
            s.WelcomeText,
            s.OnboardingJson,
            s.CustomerSplashUrl,
            s.DriverSplashUrl,
            s.SplashBackground1Url,
            s.SplashBackground2Url,
            s.LogoUrl,
            s.ClosedScreenImageUrl,
            s.SupportPhone,
            s.SupportWhatsApp,
            s.FacebookUrl,
            s.InstagramUrl,
            s.TelegramUrl,
            s.RestaurantLat,
            s.RestaurantLng,
            s.RoutingProfile,
            s.DriverSpeedBikeKmH,
            s.DriverSpeedCarKmH,
            updatedAtUtc = s.UpdatedAtUtc
        };
        await _notifyHub.Clients.All.SendAsync("settings_updated", payload);
        return Ok(payload);
    }

    [HttpGet("driver-tracks/{driverId:int}")]
    public async Task<IActionResult> DriverTracks(int driverId, [FromQuery] int minutes = 2)
    {
        minutes = Math.Clamp(minutes, 1, 10);
        var since = DateTime.UtcNow.AddMinutes(-minutes);
        var pts = await _db.DriverTrackPoints.AsNoTracking()
            .Where(p => p.DriverId == driverId && p.CreatedAtUtc >= since)
            .OrderBy(p => p.CreatedAtUtc)
            .Select(p => new { p.Lat, p.Lng, p.SpeedMps, p.HeadingDeg, p.CreatedAtUtc })
            .ToListAsync();
        return Ok(new { driverId, minutes, points = pts });
    }

    [HttpGet("order-tracks/{orderId:int}")]
    public async Task<IActionResult> OrderTracks(int orderId)
    {
        var o = await _db.Orders.AsNoTracking().FirstOrDefaultAsync(x => x.Id == orderId);
        if (o == null) return NotFound(new { error = "not_found" });

        var pts = await _db.DriverTrackPoints.AsNoTracking()
            .Where(p => p.OrderId == orderId)
            .OrderBy(p => p.CreatedAtUtc)
            .Select(p => new { p.Lat, p.Lng, p.SpeedMps, p.HeadingDeg, p.CreatedAtUtc })
            .ToListAsync();

        return Ok(new { orderId, distanceKm = Math.Round(o.DistanceKm, 3), points = pts });
    }

    [HttpGet("live-map")]
    public async Task<IActionResult> LiveMapData()
    {
        var s = await _db.RestaurantSettings.AsNoTracking().FirstAsync();
        // NOTE: We must not reference a "custMap" that is out of scope.
        // Fetch active orders first, then map customer info to avoid N+1 and keep the action compile-safe.
        var activeRaw = await _db.Orders.AsNoTracking()
            .Where(o => o.CurrentStatus != OrderStatus.Delivered && o.CurrentStatus != OrderStatus.Cancelled)
            .OrderByDescending(o => o.CreatedAtUtc)
            .Select(o => new
            {
                o.Id,
                o.DriverId,
                o.CustomerId,
                o.CurrentStatus,
                o.DeliveryLat,
                o.DeliveryLng,
                o.DeliveryAddress,
                o.Total,
                o.DistanceKm,
                o.CreatedAtUtc
            })
            .ToListAsync();

        var custIds = activeRaw.Select(x => x.CustomerId).Distinct().ToList();
        var custMap = await _db.Customers.AsNoTracking()
            .Where(c => custIds.Contains(c.Id))
            .Select(c => new { c.Id, c.Name, c.Phone })
            .ToDictionaryAsync(c => c.Id, c => new { c.Name, c.Phone });

        var active = activeRaw.Select(o => new
        {
            o.Id,
            o.DriverId,
            o.CustomerId,
            customerName = custMap.TryGetValue(o.CustomerId, out var cust1) ? (cust1.Name ?? string.Empty) : string.Empty,
            customerPhone = custMap.TryGetValue(o.CustomerId, out var cust2) ? cust2.Phone : null,
            o.CurrentStatus,
            o.DeliveryLat,
            o.DeliveryLng,
            o.DeliveryAddress,
            o.Total,
            o.DistanceKm,
            o.CreatedAtUtc
        }).ToList();

        var driverIds = active.Where(x => x.DriverId != null).Select(x => x.DriverId!.Value).Distinct().ToList();
        var locs = await _db.DriverLocations.AsNoTracking().Where(l => driverIds.Contains(l.DriverId)).ToListAsync();
        var driverNames = await _db.Drivers.AsNoTracking()
            .Where(d => driverIds.Contains(d.Id))
            .Select(d => new { d.Id, d.Name })
            .ToDictionaryAsync(d => d.Id, d => d.Name ?? $"سائق #{d.Id}");

        // Compute each driver's current "destination" to display in the live map (where are they going).
        // Rule: Prefer an order in WithDriver, otherwise the most recent active order for that driver.
        var driverTargets = active
            .Where(x => x.DriverId != null)
            .GroupBy(x => x.DriverId!.Value)
            .Select(g =>
            {
                var chosen = g.OrderByDescending(x => x.CurrentStatus == OrderStatus.WithDriver)
                              .ThenByDescending(x => x.CreatedAtUtc)
                              .First();
                var toRestaurant = chosen.CurrentStatus != OrderStatus.WithDriver;
                var tLat = toRestaurant ? s.RestaurantLat : chosen.DeliveryLat;
                var tLng = toRestaurant ? s.RestaurantLng : chosen.DeliveryLng;

                // Fallback if restaurant coords are missing.
                if (toRestaurant && (tLat == 0 || tLng == 0) && (chosen.DeliveryLat != 0 && chosen.DeliveryLng != 0))
                {
                    toRestaurant = false;
                    tLat = chosen.DeliveryLat;
                    tLng = chosen.DeliveryLng;
                }

                var label = toRestaurant ? "المطعم (استلام)" : $"الزبون (تسليم) – طلب #{chosen.Id}";
                return new { driverId = g.Key, orderId = chosen.Id, targetLat = tLat, targetLng = tLng, targetLabel = label, toRestaurant };
            })
            .ToList();


        return Ok(new
        {
            restaurant = new { lat = s.RestaurantLat, lng = s.RestaurantLng, name = s.RestaurantName, logoUrl = s.LogoUrl, routingProfile = s.RoutingProfile },
            orders = active,
            driverTargets,
            driverLocations = locs.Select(l => new { l.DriverId, driverName = driverNames.TryGetValue(l.DriverId, out var dn) ? dn : $"سائق #{l.DriverId}", l.Lat, l.Lng, l.SpeedMps, l.HeadingDeg, l.AccuracyMeters, l.UpdatedAtUtc })
        });
    }

    [HttpGet("order/{id:int}/kitchen-print")]
    public async Task<IActionResult> KitchenPrint(int id)
    {
        var o = await _db.Orders.AsNoTracking()
            .Include(x => x.Items)
            .Include(x => x.Customer)
            .Include(x => x.StatusHistory)
            .FirstOrDefaultAsync(x => x.Id == id);
        if (o == null) return NotFound();

        string esc(string s) => System.Net.WebUtility.HtmlEncode(s ?? "");

        var itemsHtml = "";
        foreach (var it in o.Items.OrderBy(x => x.Id))
        {
            var opts = (it.OptionsSnapshot ?? "").Trim();
            var modsLine = "";
            try
            {
                using var doc = System.Text.Json.JsonDocument.Parse(opts);
                var parts = new List<string>();

                // Variant
                if (doc.RootElement.TryGetProperty("variantName", out var vName) && vName.ValueKind == System.Text.Json.JsonValueKind.String)
                {
                    var vn = (vName.GetString() ?? "").Trim();
                    if (!string.IsNullOrWhiteSpace(vn)) parts.Add($"• النوع: {esc(vn)}");
                }

                // Addons/Options (normalized snapshot stores array of objects)
                if (doc.RootElement.TryGetProperty("addons", out var addons) && addons.ValueKind == System.Text.Json.JsonValueKind.Array)
                {
                    foreach (var a in addons.EnumerateArray())
                    {
                        if (a.ValueKind != System.Text.Json.JsonValueKind.Object) continue;
                        // Support both camelCase and PascalCase snapshots.
                        if (a.TryGetProperty("name", out var nEl) && nEl.ValueKind == System.Text.Json.JsonValueKind.String)
                        {
                            var n = (nEl.GetString() ?? "").Trim();
                            if (!string.IsNullOrWhiteSpace(n)) parts.Add("• " + esc(n));
                        }
                        else if (a.TryGetProperty("Name", out var nEl2) && nEl2.ValueKind == System.Text.Json.JsonValueKind.String)
                        {
                            var n = (nEl2.GetString() ?? "").Trim();
                            if (!string.IsNullOrWhiteSpace(n)) parts.Add("• " + esc(n));
                        }
                    }
                }

                // Note
                if (doc.RootElement.TryGetProperty("note", out var noteEl) && noteEl.ValueKind == System.Text.Json.JsonValueKind.String)
                {
                    var note = (noteEl.GetString() ?? "").Trim();
                    if (!string.IsNullOrWhiteSpace(note)) parts.Add($"• ملاحظة: {esc(note)}");
                }

                if (parts.Count > 0)
                    modsLine = "<div class='mods'>" + string.Join("<br/>", parts) + "</div>";
            }
            catch { /* ignore */ }

            itemsHtml += $@"<div class='item'>
  <div class='row'>
    <div class='name'>{esc(it.ProductNameSnapshot)}</div>
    <div class='qty'>× {it.Quantity}</div>
  </div>
  {modsLine}
</div>";
        }

        var phone = o.Customer?.Phone ?? "";
        var created = o.CreatedAtUtc.ToLocalTime().ToString("yyyy-MM-dd HH:mm");
        var html = $@"<!doctype html>
<html lang='ar' dir='rtl'>
<head>
<meta charset='utf-8'/>
<meta name='viewport' content='width=device-width, initial-scale=1'/>
<title>طباعة مطبخ - طلب #{o.Id}</title>
<style>
  body{{ font-family: Arial, sans-serif; margin:0; padding:18px; direction:rtl; text-align:right; }}
  .ticket{{ border:2px solid #000; border-radius:12px; padding:14px; direction:rtl; text-align:right; }}
  .orderNo{{ font-size:38px; font-weight:900; text-align:center; margin:0 0 8px; }}
  .meta{{ display:flex; justify-content:space-between; gap:12px; font-size:14px; margin-bottom:10px; }}
  .items{{ border-top:1px dashed #000; padding-top:10px; }}
  .item{{ padding:8px 0; border-bottom:1px dashed #ccc; }}
  .row{{ display:flex; justify-content:space-between; gap:10px; align-items:flex-start; }}
  .name{{ font-size:18px; font-weight:800; }}
  .qty{{ font-size:18px; font-weight:900; white-space:nowrap; }}
  .mods{{ margin-top:6px; font-size:14px; }}
  .footer{{ margin-top:10px; font-size:12px; text-align:center; color:#333; }}
  @media print {{
    body{{ padding:0; }}
    .noPrint{{ display:none; }}
    .ticket{{ border:none; border-radius:0; }}
  }}
</style>
</head>
<body>
  <div class='noPrint' style='margin-bottom:10px; display:flex; gap:8px;'>
    <button onclick='window.print()' style='padding:10px 14px; font-size:16px;'>🖨️ طباعة</button>
    <button onclick='window.close()' style='padding:10px 14px; font-size:16px;'>إغلاق</button>
  </div>
  <div class='ticket'>
    <div class='orderNo'>طلب رقم #{o.Id}</div>
    <div class='meta'>
      <div>الوقت: <b>{esc(created)}</b></div>
      <div>هاتف الزبون: <b>{esc(phone)}</b></div>
    </div>
    <div class='items'>
      {itemsHtml}
    </div>
    <div class='footer'>طباعة مطبخ</div>
  </div>
<script>setTimeout(()=>{{/* keep */}}, 50);</script>
</body>
</html>";

        return Content(html, "text/html; charset=utf-8");
    }

    /// <summary>تحويل المبلغ إلى كلمات بالعربية (ليرة سورية) للإيصال.</summary>
    private static string AmountToWordsSyrian(decimal amount)
    {
        var whole = (int)decimal.Truncate(amount);
        if (whole <= 0) return "فقط صفر ليرة سورية";
        if (whole == 1) return "فقط ليرة واحدة سورية";
        if (whole == 2) return "فقط ليرتان سوريتان";
        return "فقط " + IntToArabicWords(whole) + " ليرة سورية";
    }

    private static readonly string[] OnesM = { "", "واحد", "اثنان", "ثلاثة", "أربعة", "خمسة", "ستة", "سبعة", "ثمانية", "تسعة" };
    private static readonly string[] Tens = { "", "عشر", "عشرون", "ثلاثون", "أربعون", "خمسون", "ستون", "سبعون", "ثمانون", "تسعون" };
    private static readonly string[] TensFrom10 = { "عشر", "إحدى عشرة", "اثنتا عشرة", "ثلاث عشرة", "أربع عشرة", "خمس عشرة", "ست عشرة", "سبع عشرة", "ثمان عشرة", "تسع عشرة" };
    private static readonly string[] Hundreds = { "", "مئة", "مئتان", "ثلاثمئة", "أربعمئة", "خمسمئة", "ستمئة", "سبعمئة", "ثمانمئة", "تسعمئة" };

    private static string IntToArabicWords(int n)
    {
        if (n == 0) return "صفر";
        if (n < 0) return "سالب " + IntToArabicWords(-n);
        if (n >= 1000)
        {
            var thousands = n / 1000;
            var rest = n % 1000;
            var t = thousands == 1 ? "ألف" : (thousands == 2 ? "ألفان" : IntToArabicWords(thousands) + " آلاف");
            if (thousands > 10) t = IntToArabicWords(thousands) + " ألف";
            return rest == 0 ? t : t + " و" + IntToArabicWords(rest);
        }
        if (n >= 100)
        {
            var h = n / 100;
            var rest = n % 100;
            var hr = Hundreds[h];
            if (h == 1 && rest > 0) hr = "مئة";
            return rest == 0 ? hr : hr + " و" + IntToArabicWords(rest);
        }
        if (n >= 20)
        {
            var ten = n / 10;
            var one = n % 10;
            return one == 0 ? Tens[ten] : OnesM[one] + " و" + Tens[ten];
        }
        if (n >= 10) return TensFrom10[n - 10];
        return OnesM[n];
    }

    /// <summary>
    /// صفحة receipt-print لم تعد تعرض الإيصال. الطباعة تتم فقط من تطبيق الويندوز.
    /// عند فتح هذا الرابط يُعرض تنبيه فقط.
    /// </summary>
    [HttpGet("order/{id:int}/receipt-print")]
    public async Task<IActionResult> ReceiptPrint(int id, [FromQuery] string? paper = null, [FromQuery] int? autoprint = null, [FromQuery] string? target = null)
    {
        var o = await _db.Orders.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id);
        if (o == null) return NotFound();

        var msg = "الطباعة تتم من تطبيق الويندوز فقط. استخدم زر «طباعة» في لوحة الطلبات داخل تطبيق توب شيف للويندوز.";
        var html = $@"<!doctype html>
<html lang='ar' dir='rtl'>
<head><meta charset='utf-8'/></head>
<body style='font-family:Arial;padding:24px;text-align:center;max-width:400px;margin:40px auto;'>
  <p style='font-size:16px;'>{System.Net.WebUtility.HtmlEncode(msg)}</p>
  <p><small>طلب #{o.Id}</small></p>
  <button onclick='window.close()' style='padding:10px 16px;'>إغلاق</button>
</body>
</html>";
        return Content(html, "text/html; charset=utf-8");
    }

}
