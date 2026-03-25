using AdminDashboard.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AdminDashboard.Controllers;

[ApiController]
[Route("api/admin/ratings")]
[Authorize(Policy = "AdminOnly")]
public class AdminRatingsController : ControllerBase
{
    private readonly AppDbContext _db;

    public AdminRatingsController(AppDbContext db)
    {
        _db = db;
    }

    // Admin ratings view (Food + Driver) with optional search.
    // NOTE: Keep EF query separate from in-memory filtering (StringComparison is not EF-translatable).
    [HttpGet]
    public async Task<IActionResult> Get(
        [FromQuery] DateTime? fromUtc = null,
        [FromQuery] DateTime? toUtc = null,
        [FromQuery(Name = "q")] string? search = null)
    {
        var ratingsQ = _db.OrderRatings.AsNoTracking().AsQueryable();

        if (fromUtc != null) ratingsQ = ratingsQ.Where(r => r.CreatedAtUtc >= fromUtc.Value);
        if (toUtc != null) ratingsQ = ratingsQ.Where(r => r.CreatedAtUtc < toUtc.Value);

        var ratings = await ratingsQ
            .OrderByDescending(r => r.CreatedAtUtc)
            .Take(1000)
            .ToListAsync();

        // Load related (customer/driver) in bulk
        var orderIds = ratings.Select(r => r.OrderId).Distinct().ToList();
        var orders = await _db.Orders.AsNoTracking()
            .Where(o => orderIds.Contains(o.Id))
            .Select(o => new { o.Id, o.CustomerId, o.DriverId })
            .ToListAsync();
        var orderMap = orders.ToDictionary(x => x.Id);

        var customerIds = orders.Select(o => o.CustomerId).Distinct().ToList();
        var driverIds = orders.Where(o => o.DriverId != null).Select(o => o.DriverId!.Value).Distinct().ToList();

        var customers = await _db.Customers.AsNoTracking()
            .Where(c => customerIds.Contains(c.Id))
            .Select(c => new { c.Id, c.Name, c.Phone })
            .ToListAsync();
        var customerMap = customers.ToDictionary(c => c.Id);

        var drivers = await _db.Drivers.AsNoTracking()
            .Where(d => driverIds.Contains(d.Id))
            .Select(d => new { d.Id, d.Name, d.Phone })
            .ToListAsync();
        var driverMap = drivers.ToDictionary(d => d.Id);

        static double? Avg(IEnumerable<int> xs)
        {
            var vals = xs.Where(x => x >= 1 && x <= 5).Select(x => (double)x).ToList();
            if (vals.Count == 0) return null;
            return Math.Round(vals.Average(), 2);
        }

        var restaurantAvg = Avg(ratings.Select(r => r.RestaurantRate));
        var driverAvg = Avg(ratings.Select(r => r.DriverRate));
        var count = ratings.Count;

        var perDriver = ratings
            .Select(r => new { r, order = orderMap.TryGetValue(r.OrderId, out var o) ? o : null })
            .Where(x => x.order?.DriverId != null)
            .GroupBy(x => x.order!.DriverId!.Value)
            .Select(g => new
            {
                driverId = g.Key,
                driver = driverMap.TryGetValue(g.Key, out var d) ? d : null,
                avg = Avg(g.Select(x => x.r.DriverRate)),
                count = g.Count()
            })
            .OrderByDescending(x => x.avg ?? 0)
            .ThenByDescending(x => x.count)
            .ToList();

        var items = ratings.Select(r =>
        {
            orderMap.TryGetValue(r.OrderId, out var o);
            var cust = (o != null && customerMap.TryGetValue(o.CustomerId, out var c)) ? c : null;
            var drv = (o != null && o.DriverId != null && driverMap.TryGetValue(o.DriverId.Value, out var d)) ? d : null;

            return new
            {
                orderId = r.OrderId,
                restaurantRate = r.RestaurantRate,
                driverRate = r.DriverRate,
                comment = r.Comment,
                createdAtUtc = r.CreatedAtUtc,
                customer = cust,
                driver = drv
            };
        }).ToList();

        // Optional in-memory search
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim();
            if (int.TryParse(s, out var oid))
            {
                items = items.Where(x => x.orderId == oid).ToList();
            }
            else
            {
                items = items.Where(x =>
                    (x.customer != null && (
                        (!string.IsNullOrWhiteSpace(x.customer.Name) && x.customer.Name.Contains(s, StringComparison.OrdinalIgnoreCase)) ||
                        (!string.IsNullOrWhiteSpace(x.customer.Phone) && x.customer.Phone.Contains(s, StringComparison.OrdinalIgnoreCase))
                    )) ||
                    (x.driver != null && (
                        (!string.IsNullOrWhiteSpace(x.driver.Name) && x.driver.Name.Contains(s, StringComparison.OrdinalIgnoreCase)) ||
                        (!string.IsNullOrWhiteSpace(x.driver.Phone) && x.driver.Phone.Contains(s, StringComparison.OrdinalIgnoreCase))
                    ))
                ).ToList();
            }
        }

        return Ok(new
        {
            items,
            averages = new { restaurant = restaurantAvg, driver = driverAvg },
            count,
            perDriver
        });
    }
}
