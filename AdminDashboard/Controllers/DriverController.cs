using AdminDashboard.Data;
using AdminDashboard.Entities;
using AdminDashboard.Hubs;
using AdminDashboard.Security;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace AdminDashboard.Controllers;

[ApiController]
[Route("api/driver")]
public class DriverController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IOptions<AppSecurityOptions> _opts;
    private readonly IHubContext<TrackingHub> _trackingHub;
    private readonly IHubContext<NotifyHub> _notifyHub;
    private readonly NotificationService _notifications;

    // Distance helper (km) - kept at class scope so it can be used by multiple endpoints.
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

    // Normalize speed to meters/second with safety clamps and unit-guessing.
    // - Preferred: SpeedKmh (km/h)
    // - Legacy: SpeedMps (m/s)
    // - Defensive: if SpeedMps is unrealistically high, assume the client accidentally sent km/h.
    private static double NormalizeSpeedMps(LocationReq req)
    {
        const double maxKmh = 160.0; // market-safe upper bound
        var maxMps = maxKmh / 3.6;

        if (req.SpeedKmh.HasValue)
        {
            var kmh = Math.Clamp(req.SpeedKmh.Value, 0.0, maxKmh);
            return Math.Clamp(kmh / 3.6, 0.0, maxMps);
        }

        var mps = req.SpeedMps;
        if (double.IsNaN(mps) || double.IsInfinity(mps) || mps < 0) mps = 0;

        // If mps is > 80 m/s (288 km/h) it is almost certainly km/h mistakenly.
        if (mps > 80.0)
        {
            var kmh = Math.Clamp(mps, 0.0, maxKmh);
            return Math.Clamp(kmh / 3.6, 0.0, maxMps);
        }

        return Math.Clamp(mps, 0.0, maxMps);
    }

    public DriverController(AppDbContext db, IOptions<AppSecurityOptions> opts, IHubContext<TrackingHub> trackingHub, IHubContext<NotifyHub> notifyHub, NotificationService notifications)
    {
        _db = db;
        _opts = opts;
        _trackingHub = trackingHub;
        _notifyHub = notifyHub;
        _notifications = notifications;
    }

    public record LoginReq(string Phone, string Pin);

    [HttpPost("login")]
    public async Task<IActionResult> Login(LoginReq req)
    {
        var d = await _db.Drivers.FirstOrDefaultAsync(x => x.Phone == req.Phone && x.Pin == req.Pin);
        if (d == null) return Unauthorized(new { error = "بيانات الدخول غير صحيحة" });

        d.Status = DriverStatus.Available;
        await _db.SaveChangesAsync();

        var token = DriverAuth.IssueToken(d.Id, _opts);
        await _notifyHub.Clients.Group("admin").SendAsync("driver_status", new { driverId = d.Id, status = d.Status });

        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Admin, null,
            "سائق متصل", $"السائق {d.Name} أصبح متصلاً", null);

        return Ok(new { token, driver = new { d.Id, d.Name, d.Phone, d.VehicleType, d.Status, d.PhotoUrl } });
    }

    private bool TryGetDriverId(out int driverId)
    {
        driverId = 0;
        if (!Request.Headers.TryGetValue("X-DRIVER-TOKEN", out var token)) return false;
        return DriverAuth.TryValidate(token!, _opts, out driverId);
    }

    [HttpPost("logout")]
    public async Task<IActionResult> Logout()
    {
        if (!TryGetDriverId(out var driverId)) return Unauthorized(new { error = "unauthorized" });
        var d = await _db.Drivers.FirstOrDefaultAsync(x => x.Id == driverId);
        if (d == null) return Unauthorized(new { error = "unauthorized" });
        d.Status = DriverStatus.Offline;
        await _db.SaveChangesAsync();
        await _notifyHub.Clients.Group("admin").SendAsync("driver_status", new { driverId = d.Id, status = d.Status });
        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Admin, null,
            "سائق غير متصل", $"السائق {d.Name} قام بتسجيل الخروج", null);
        return Ok(new { ok = true });
    }

    [HttpGet("me")]
    public async Task<IActionResult> Me()
    {
        if (!TryGetDriverId(out var driverId)) return Unauthorized(new { error = "unauthorized" });
        var d = await _db.Drivers.AsNoTracking().FirstOrDefaultAsync(x => x.Id == driverId);
        if (d == null) return Unauthorized(new { error = "unauthorized" });
        return Ok(new { d.Id, d.Name, d.Phone, d.VehicleType, d.Status, d.PhotoUrl });
    }

    [HttpGet("current-order")]
    public async Task<IActionResult> CurrentOrder()
    {
        if (!TryGetDriverId(out var driverId)) return Unauthorized(new { error = "unauthorized" });

        var o = await _db.Orders.AsNoTracking()
            .Where(x => x.DriverId == driverId && x.CurrentStatus != OrderStatus.Delivered && x.CurrentStatus != OrderStatus.Cancelled)
            .OrderByDescending(x => x.CreatedAtUtc)
            .FirstOrDefaultAsync();

        if (o == null) return Ok(new { hasOrder = false });

        var s = await _db.RestaurantSettings.AsNoTracking().FirstOrDefaultAsync();
        var restaurantLat = s?.RestaurantLat ?? 0.0;
        var restaurantLng = s?.RestaurantLng ?? 0.0;

        return Ok(new
        {
            hasOrder = true,
            o.Id,
            o.CurrentStatus,
            o.DeliveryLat,
            o.DeliveryLng,
            o.DeliveryAddress,
            restaurantLat,
            restaurantLng,
            o.Notes,
            o.Total
        });
    }

    [HttpGet("active-orders")]
    public async Task<IActionResult> ActiveOrders()
    {
        if (!TryGetDriverId(out var driverId)) return Unauthorized(new { error = "unauthorized" });

        var s = await _db.RestaurantSettings.AsNoTracking().FirstOrDefaultAsync();
        var restaurantLat = s?.RestaurantLat ?? 0.0;
        var restaurantLng = s?.RestaurantLng ?? 0.0;

        var driver = await _db.Drivers.AsNoTracking().FirstOrDefaultAsync(d => d.Id == driverId);
        var vehicleType = driver?.VehicleType ?? VehicleType.Car;
        var bikeSpeed = (double?)(s?.DriverSpeedBikeKmH) ?? 18.0;
        var carSpeed = (double?)(s?.DriverSpeedCarKmH) ?? 30.0;
        var speedKmH = vehicleType == VehicleType.Bike ? bikeSpeed : carSpeed;
        if (speedKmH <= 0) speedKmH = 30.0;

        var ordersRaw = await _db.Orders.AsNoTracking()
            .Include(o => o.Customer)
            .Where(o => o.DriverId == driverId && o.CurrentStatus != OrderStatus.Delivered && o.CurrentStatus != OrderStatus.Cancelled)
            .OrderByDescending(o => o.CreatedAtUtc)
            .Take(10)
            .Select(o => new
            {
                o.Id,
                o.CurrentStatus,
                o.DeliveryLat,
                o.DeliveryLng,
                o.DeliveryAddress,
                o.Notes,
                o.Total,
                customerName = o.Customer != null ? o.Customer.Name : "",
                customerPhone = o.Customer != null ? o.Customer.Phone : ""
            })
            .ToListAsync();

        var orders = ordersRaw.Select(o =>
        {
            var lat = o.DeliveryLat;
            var lng = o.DeliveryLng;
            int? etaMinutes = null;
            if (restaurantLat != 0 && restaurantLng != 0 && lat != 0 && lng != 0)
            {
                var km = HaversineKm(restaurantLat, restaurantLng, lat, lng);
                etaMinutes = (int)Math.Max(1, Math.Round((km / speedKmH) * 60.0));
            }
            return new
            {
                o.Id,
                o.CurrentStatus,
                o.DeliveryLat,
                o.DeliveryLng,
                o.DeliveryAddress,
                o.Notes,
                o.Total,
                o.customerName,
                o.customerPhone,
                etaMinutes
            };
        }).ToList();

        return Ok(new { restaurantLat, restaurantLng, vehicleType, speedKmH, orders });
    }

    public record UpdateOrderStatusReq(int OrderId, OrderStatus Status, string? Comment);

    [HttpPost("order-status")]
    public async Task<IActionResult> UpdateOrderStatus(UpdateOrderStatusReq req)
    {
        if (!TryGetDriverId(out var driverId)) return Unauthorized(new { error = "unauthorized" });
        var o = await _db.Orders.FirstOrDefaultAsync(x => x.Id == req.OrderId && x.DriverId == driverId);
        if (o == null) return NotFound(new { error = "not_found" });

        o.CurrentStatus = req.Status;
        _db.OrderStatusHistory.Add(new OrderStatusHistory { OrderId = o.Id, Status = req.Status, Comment = req.Comment, ChangedByType = "driver", ChangedById = driverId });

        // Mark driver confirmation once (used for reports/analytics).
        if (req.Status == OrderStatus.WithDriver && o.DriverConfirmedAtUtc == null)
        {
            o.DriverConfirmedAtUtc = DateTime.UtcNow;
        }

        if (req.Status == OrderStatus.WithDriver)
        {
            var d = await _db.Drivers.FindAsync(driverId);
            if (d != null) d.Status = DriverStatus.Busy;
        }
        
       if (req.Status == OrderStatus.Delivered)
{
    // السماح للسائق بإنهاء التسليم من أي مكان (إلغاء شرط القرب من موقع الزبون)
    o.DeliveredAtUtc = DateTime.UtcNow;

    var d = await _db.Drivers.FindAsync(driverId);
    if (d != null) d.Status = DriverStatus.Available;
}

        await _db.SaveChangesAsync();

        await _notifyHub.Clients.Group("admin").SendAsync("order_status", new { orderId = o.Id, status = o.CurrentStatus, driverId = o.DriverId });
        await _notifyHub.Clients.Group($"customer-{o.CustomerId}").SendAsync("order_status", new { orderId = o.Id, status = o.CurrentStatus, driverId = o.DriverId });

      
// ترجمة حالة الطلب للعربية
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

        // Customer push: 3 notifications only (Accepted/Preparing, OutForDelivery, Delivered)
        await _notifications.SendCustomerOrderStatusPushIfNeededAsync(o.CustomerId, o.Id, o.CurrentStatus, o.PrepEtaMinutes, o.DeliveryEtaMinutes);
        return Ok(new { ok = true });
    }

    // NOTE: clients historically send speedMps (meters/second). Some web/debug clients may send km/h by mistake.
    // We accept an optional speedKmh and normalize defensively so the Admin LiveMap shows realistic values.
    public record LocationReq(double Lat, double Lng, double SpeedMps, double HeadingDeg, double AccuracyMeters, double? SpeedKmh = null);

    public record LocationBatchReq(List<LocationReq> Points);

    public record CancelOrderReq(string? Reason);

    [HttpPost("order/{orderId:int}/cancel")]
    public async Task<IActionResult> CancelOrder(int orderId, CancelOrderReq req)
    {
        if (!TryGetDriverId(out var driverId)) return Unauthorized(new { error = "unauthorized" });

        var o = await _db.Orders.FirstOrDefaultAsync(x => x.Id == orderId && x.DriverId == driverId);
        if (o == null) return NotFound(new { error = "not_found" });

        if (o.CurrentStatus == OrderStatus.Delivered || o.CurrentStatus == OrderStatus.Cancelled)
            return BadRequest(new { error = "cannot_cancel", message = "لا يمكن إلغاء هذا الطلب" });

        // Market rule requested: driver can cancel anytime before Delivered.
        // This cancels the ORDER (not just unassign) so admin sees "ملغي من قبل السائق".
        o.CurrentStatus = OrderStatus.Cancelled;
        o.CancelReasonCode = "driver_cancel";

        var comment = string.IsNullOrWhiteSpace(req.Reason) ? null : req.Reason.Trim();
        _db.OrderStatusHistory.Add(new OrderStatusHistory
        {
            OrderId = o.Id,
            Status = OrderStatus.Cancelled,
            ReasonCode = "driver_cancel",
            Comment = "ملغي من قبل السائق" + (comment == null ? "" : $" — {comment}"),
            ChangedByType = "driver",
            ChangedById = driverId,
            ChangedAtUtc = DateTime.UtcNow
        });

        var d = await _db.Drivers.FindAsync(driverId);
        if (d != null) d.Status = DriverStatus.Available;

        await _db.SaveChangesAsync();

        // Realtime update to admin + customer
        await _notifyHub.Clients.Group("admin").SendAsync("order_status", new { orderId = o.Id, status = o.CurrentStatus, driverId = o.DriverId });
        await _notifyHub.Clients.Group($"customer-{o.CustomerId}").SendAsync("order_status", new { orderId = o.Id, status = o.CurrentStatus, driverId = o.DriverId });

        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Admin, null,
            "إلغاء من السائق", $"السائق ألغى الطلب #{o.Id}" + (comment == null ? "" : $" — {comment}"), o.Id);

        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Customer, o.CustomerId,
            "تحديث الطلب", $"تم إلغاء الطلب #{o.Id} من قبل السائق.", o.Id);

        return Ok(new { ok = true });
    }

    [HttpPost("location")]
    public async Task<IActionResult> UpsertLocation(LocationReq req)
    {
        if (!TryGetDriverId(out var driverId)) return Unauthorized(new { error = "unauthorized" });

        var (activeOrder, loc) = await UpsertLocationCore(driverId, req);

        // Always broadcast to admin while the driver has any active (non-delivered/non-cancelled) orders.
        // Customer tracking remains limited to the in-delivery state for privacy.
        var adminOrders = await _db.Orders.AsNoTracking()
            .Where(o => o.DriverId == driverId && o.CurrentStatus != OrderStatus.Delivered && o.CurrentStatus != OrderStatus.Cancelled)
            .OrderByDescending(o => o.CreatedAtUtc)
            .Select(o => new { o.Id, o.CurrentStatus })
            .Take(10)
            .ToListAsync();
        if (adminOrders.Count > 0)
        {
            var adminPayload = new
            {
                driverId,
                lat = loc.Lat,
                lng = loc.Lng,
                speedMps = loc.SpeedMps,
                headingDeg = loc.HeadingDeg,
                accuracyMeters = loc.AccuracyMeters,
                updatedAtUtc = loc.UpdatedAtUtc,
                activeOrders = adminOrders
            };
            await _trackingHub.Clients.Group("admin").SendAsync("driver_location", adminPayload);
            await _trackingHub.Clients.Group("admin").SendAsync("driver_location_updated", adminPayload);
        }

        // Broadcast only to admin + the customer of the active order (privacy)
        if (activeOrder != null && activeOrder.CurrentStatus == OrderStatus.WithDriver)
        {
            var payload = new
            {
                orderId = activeOrder.Id,
                driverId,
                lat = loc.Lat,
                lng = loc.Lng,
                speedMps = loc.SpeedMps,
                headingDeg = loc.HeadingDeg,
                accuracyMeters = loc.AccuracyMeters,
                updatedAtUtc = loc.UpdatedAtUtc
            };

            // Customer-specific tracking
            await _trackingHub.Clients.Group($"customer-{activeOrder.CustomerId}").SendAsync("driver_location", payload);
            await _trackingHub.Clients.Group($"customer-{activeOrder.CustomerId}").SendAsync("driver_location_updated", payload);
        }

        return Ok(new { ok = true });
    }

    [HttpPost("location/batch")]
    public async Task<IActionResult> UpsertLocationBatch(LocationBatchReq req)
    {
        if (!TryGetDriverId(out var driverId)) return Unauthorized(new { error = "unauthorized" });
        if (req.Points == null || req.Points.Count == 0) return Ok(new { ok = true });

        // To reduce DB chatter, we process points sequentially but broadcast only the last location.
        (dynamic? activeOrder, DriverLocation? lastLoc) result = (null, null);
        foreach (var p in req.Points)
        {
            result = await UpsertLocationCore(driverId, p);
        }

        var activeOrder = result.activeOrder;
        var loc = result.lastLoc;
        if (loc == null) return Ok(new { ok = true });

        // Admin broadcast (same logic as single-point)
        var adminOrders = await _db.Orders.AsNoTracking()
            .Where(o => o.DriverId == driverId && o.CurrentStatus != OrderStatus.Delivered && o.CurrentStatus != OrderStatus.Cancelled)
            .OrderByDescending(o => o.CreatedAtUtc)
            .Select(o => new { o.Id, o.CurrentStatus })
            .Take(10)
            .ToListAsync();
        if (adminOrders.Count > 0)
        {
            var adminPayload = new
            {
                driverId,
                lat = loc.Lat,
                lng = loc.Lng,
                speedMps = loc.SpeedMps,
                headingDeg = loc.HeadingDeg,
                accuracyMeters = loc.AccuracyMeters,
                updatedAtUtc = loc.UpdatedAtUtc,
                activeOrders = adminOrders
            };
            await _trackingHub.Clients.Group("admin").SendAsync("driver_location", adminPayload);
            await _trackingHub.Clients.Group("admin").SendAsync("driver_location_updated", adminPayload);
        }

        // Customer broadcast only when the delivery has started.
        if (activeOrder != null && activeOrder.CurrentStatus == OrderStatus.WithDriver)
        {
            var payload = new
            {
                orderId = activeOrder.Id,
                driverId,
                lat = loc.Lat,
                lng = loc.Lng,
                speedMps = loc.SpeedMps,
                headingDeg = loc.HeadingDeg,
                accuracyMeters = loc.AccuracyMeters,
                updatedAtUtc = loc.UpdatedAtUtc
            };
            await _trackingHub.Clients.Group($"customer-{activeOrder.CustomerId}").SendAsync("driver_location", payload);
            await _trackingHub.Clients.Group($"customer-{activeOrder.CustomerId}").SendAsync("driver_location_updated", payload);
        }

        return Ok(new { ok = true });
    }

    private async Task<(dynamic? activeOrder, DriverLocation loc)> UpsertLocationCore(int driverId, LocationReq req)
    {
        // Only track/broadcast while there is an active delivery.
        var activeOrder = await _db.Orders.AsNoTracking()
            .Where(o => o.DriverId == driverId && o.CurrentStatus != OrderStatus.Delivered && o.CurrentStatus != OrderStatus.Cancelled)
            .OrderByDescending(o => o.CreatedAtUtc)
            .Select(o => new { o.Id, o.CustomerId, o.CurrentStatus, o.DriverConfirmedAtUtc })
            .FirstOrDefaultAsync();

        var loc = await _db.DriverLocations.FirstOrDefaultAsync(x => x.DriverId == driverId);
        if (loc == null)
        {
            loc = new DriverLocation { DriverId = driverId };
            _db.DriverLocations.Add(loc);
        }

        var normalizedSpeedMps = NormalizeSpeedMps(req);

        // Smooth speed to avoid spikes (GPS jitter / browser batching)
        // If we have a previous value, apply exponential smoothing.
        if (loc.SpeedMps > 0 && normalizedSpeedMps > 0)
        {
            normalizedSpeedMps = (loc.SpeedMps * 0.7) + (normalizedSpeedMps * 0.3);
        }

        loc.Lat = req.Lat;
        loc.Lng = req.Lng;
        loc.SpeedMps = normalizedSpeedMps;
        loc.HeadingDeg = (double.IsNaN(req.HeadingDeg) || double.IsInfinity(req.HeadingDeg)) ? 0 : req.HeadingDeg;
        loc.AccuracyMeters = (double.IsNaN(req.AccuracyMeters) || double.IsInfinity(req.AccuracyMeters)) ? 0 : req.AccuracyMeters;
        loc.UpdatedAtUtc = DateTime.UtcNow;

        // Add track point + accumulate distance only during active delivery
        if (activeOrder != null && activeOrder.CurrentStatus == OrderStatus.WithDriver)
        {
            var now = DateTime.UtcNow;

            // Compute incremental distance from the last point of this ORDER (not just driver)
            var lastPt = await _db.DriverTrackPoints.AsNoTracking()
                .Where(p => p.OrderId == activeOrder.Id)
                .OrderByDescending(p => p.CreatedAtUtc)
                .Select(p => new { p.Lat, p.Lng, p.CreatedAtUtc })
                .FirstOrDefaultAsync();

            var incKm = 0.0;
            if (lastPt != null)
            {
                incKm = HaversineKm(lastPt.Lat, lastPt.Lng, req.Lat, req.Lng);
                // Ignore unrealistic jumps (GPS spikes)
                if (incKm > 1.0) incKm = 0.0;
            }

            _db.DriverTrackPoints.Add(new DriverTrackPoint
            {
                DriverId = driverId,
                OrderId = activeOrder.Id,
                Lat = req.Lat,
                Lng = req.Lng,
                SpeedMps = normalizedSpeedMps,
                HeadingDeg = req.HeadingDeg,
                CreatedAtUtc = now
            });

            if (incKm > 0)
            {
                var ord = await _db.Orders.FirstOrDefaultAsync(x => x.Id == activeOrder.Id);
                if (ord != null)
                {
                    ord.DistanceKm = Math.Round(Math.Max(0, ord.DistanceKm) + incKm, 3);
                }
            }
        }

        await _db.SaveChangesAsync();

        // Keep last 500 points per driver
        var keep = 500;
        var cnt = await _db.DriverTrackPoints.CountAsync(x => x.DriverId == driverId);
        if (cnt > keep)
        {
            var ids = await _db.DriverTrackPoints.AsNoTracking()
                .Where(x => x.DriverId == driverId)
                .OrderByDescending(x => x.CreatedAtUtc)
                .Skip(keep)
                .Select(x => x.Id)
                .ToListAsync();
            if (ids.Count > 0)
            {
                var del = _db.DriverTrackPoints.Where(x => ids.Contains(x.Id));
                _db.DriverTrackPoints.RemoveRange(del);
                await _db.SaveChangesAsync();
            }
        }

        return (activeOrder, loc);
    }



    // Daily stats for driver (SRS): delivered count + cash collected (Delivered today).
    // Uses X-DRIVER-TOKEN like the rest of the driver API.
    [HttpGet("today-stats")]
    public async Task<IActionResult> GetTodayStats()
    {
        if (!TryGetDriverId(out var driverId)) return Unauthorized(new { error = "unauthorized" });

        var driver = await _db.Drivers.AsNoTracking().FirstOrDefaultAsync(d => d.Id == driverId);
        if (driver == null) return NotFound(new { error = "driver_not_found" });

        var localNow = DateTime.Now;
        var localStart = new DateTime(localNow.Year, localNow.Month, localNow.Day, 0, 0, 0, DateTimeKind.Local);
        var localEnd = localStart.AddDays(1);

        var startUtc = localStart.ToUniversalTime();
        var endUtc = localEnd.ToUniversalTime();

        var q = _db.Orders.AsNoTracking()
            .Where(o => o.DriverId == driverId && o.CurrentStatus == OrderStatus.Delivered && o.DeliveredAtUtc != null && o.DeliveredAtUtc >= startUtc && o.DeliveredAtUtc < endUtc);

        var deliveredCount = await q.CountAsync();
        var cashCollected = await q.SumAsync(o => (decimal?)o.Total) ?? 0m;

        return Ok(new { driverId, deliveredCount, cashCollected });
    }


}
