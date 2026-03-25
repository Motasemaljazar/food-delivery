using AdminDashboard.Data;
using AdminDashboard.Entities;
using AdminDashboard.Security;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace AdminDashboard.Controllers;

[ApiController]
[Route("api")]
public class NotificationsController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IOptions<AppSecurityOptions> _opts;

    public NotificationsController(AppDbContext db, IOptions<AppSecurityOptions> opts)
    {
        _db = db;
        _opts = opts;
    }

    [HttpGet("admin/notifications")]
    [Authorize(Policy = "AdminOnly")]
    public async Task<IActionResult> AdminNotifications([FromQuery] int limit = 50)
    {
        limit = Math.Clamp(limit, 10, 200);
        var list = await _db.Notifications.AsNoTracking()
            .Where(n => n.UserType == NotificationUserType.Admin)
            .OrderByDescending(n => n.CreatedAtUtc)
            .Take(limit)
            .ToListAsync();
        return Ok(new { notifications = list });
    }

    [HttpPost("admin/notifications/{id:int}/read")]
    [Authorize(Policy = "AdminOnly")]
    public async Task<IActionResult> AdminMarkRead(int id)
    {
        var n = await _db.Notifications.FirstOrDefaultAsync(x => x.Id == id && x.UserType == NotificationUserType.Admin);
        if (n == null) return NotFound(new { error = "not_found" });
        n.IsRead = true;
        await _db.SaveChangesAsync();
        return Ok(new { ok = true });
    }

    [HttpGet("customer/{customerId:int}/notifications")]
    public async Task<IActionResult> CustomerNotifications(int customerId, [FromQuery] int limit = 50)
    {
        limit = Math.Clamp(limit, 10, 200);
        var now = DateTime.UtcNow;
        var cutoff = now.AddDays(-7);

        // تنظيف تناظري: حذف الإشعارات المقروءة الأقدم من 7 أيام لهذا الزبون.
        var oldRead = await _db.Notifications
            .Where(n => n.UserType == NotificationUserType.Customer
                        && n.UserId == customerId
                        && n.IsRead
                        && n.CreatedAtUtc < cutoff)
            .ToListAsync();
        if (oldRead.Count > 0)
        {
            _db.Notifications.RemoveRange(oldRead);
            await _db.SaveChangesAsync();
        }

        var list = await _db.Notifications.AsNoTracking()
            .Where(n => n.UserType == NotificationUserType.Customer && n.UserId == customerId)
            .OrderByDescending(n => n.CreatedAtUtc)
            .Take(limit)
            .ToListAsync();
        return Ok(new { notifications = list });
    }

    [HttpPost("customer/{customerId:int}/notifications/{id:int}/read")]
    public async Task<IActionResult> CustomerMarkRead(int customerId, int id)
    {
        var n = await _db.Notifications.FirstOrDefaultAsync(x => x.Id == id && x.UserType == NotificationUserType.Customer && x.UserId == customerId);
        if (n == null) return NotFound(new { error = "not_found" });
        n.IsRead = true;
        await _db.SaveChangesAsync();
        return Ok(new { ok = true });
    }

    [HttpPost("customer/{customerId:int}/notifications/read-all")]
    public async Task<IActionResult> CustomerMarkAllRead(int customerId)
    {
        var list = await _db.Notifications
            .Where(n => n.UserType == NotificationUserType.Customer && n.UserId == customerId && !n.IsRead)
            .ToListAsync();
        if (list.Count == 0) return Ok(new { ok = true, updated = 0 });
        foreach (var n in list)
        {
            n.IsRead = true;
        }
        await _db.SaveChangesAsync();
        return Ok(new { ok = true, updated = list.Count });
    }

    private bool TryGetDriverId(out int driverId)
    {
        driverId = 0;
        if (!Request.Headers.TryGetValue("X-DRIVER-TOKEN", out var token)) return false;
        return DriverAuth.TryValidate(token!, _opts, out driverId);
    }

    [HttpGet("driver/notifications")]
    public async Task<IActionResult> DriverNotifications([FromQuery] int limit = 50)
    {
        if (!TryGetDriverId(out var driverId)) return Unauthorized(new { error = "unauthorized" });
        limit = Math.Clamp(limit, 10, 200);
        var list = await _db.Notifications.AsNoTracking()
            .Where(n => n.UserType == NotificationUserType.Driver && n.UserId == driverId)
            .OrderByDescending(n => n.CreatedAtUtc)
            .Take(limit)
            .ToListAsync();
        return Ok(new { notifications = list });
    }

    [HttpPost("driver/notifications/{id:int}/read")]
    public async Task<IActionResult> DriverMarkRead(int id)
    {
        if (!TryGetDriverId(out var driverId)) return Unauthorized(new { error = "unauthorized" });
        var n = await _db.Notifications.FirstOrDefaultAsync(x => x.Id == id && x.UserType == NotificationUserType.Driver && x.UserId == driverId);
        if (n == null) return NotFound(new { error = "not_found" });
        n.IsRead = true;
        await _db.SaveChangesAsync();
        return Ok(new { ok = true });
    }
}
