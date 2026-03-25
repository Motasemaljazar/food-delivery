using AdminDashboard.Data;
using AdminDashboard.Entities;
using AdminDashboard.Hubs;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace AdminDashboard.Controllers;

[ApiController]
public class RatingsController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IHubContext<NotifyHub> _hub;
    private readonly NotificationService _notifications;

    public RatingsController(AppDbContext db, IHubContext<NotifyHub> hub, NotificationService notifications)
    {
        _db = db;
        _hub = hub;
        _notifications = notifications;
    }

    public record CreateOrderRatingRequest(int OrderId, int CustomerId, int RestaurantRate, int DriverRate, string? Comment);

    [HttpPost]
    [Route("api/ratings")]
    public async Task<IActionResult> Create(CreateOrderRatingRequest req)
    {
        if (req.RestaurantRate < 1 || req.RestaurantRate > 5)
            return BadRequest(new { error = "invalid_restaurant_rate", message = "تقييم المطعم يجب أن يكون بين 1 و 5" });
        if (req.DriverRate < 1 || req.DriverRate > 5)
            return BadRequest(new { error = "invalid_driver_rate", message = "تقييم السائق يجب أن يكون بين 1 و 5" });

        var o = await _db.Orders.FirstOrDefaultAsync(x => x.Id == req.OrderId);
        if (o == null) return NotFound(new { error = "not_found" });
        if (o.CustomerId != req.CustomerId) return Forbid();
        if (o.CurrentStatus != OrderStatus.Delivered)
            return BadRequest(new { error = "not_delivered", message = "يمكن التقييم بعد تسليم الطلب فقط" });

        // If no driver, allow driverRate but store as provided.
        var existing = await _db.OrderRatings.FirstOrDefaultAsync(x => x.OrderId == o.Id);
        if (existing == null)
        {
            existing = new OrderRating
            {
                OrderId = o.Id,
                RestaurantRate = req.RestaurantRate,
                DriverRate = req.DriverRate,
                Comment = string.IsNullOrWhiteSpace(req.Comment) ? null : req.Comment.Trim(),
                CreatedAtUtc = DateTime.UtcNow
            };
            _db.OrderRatings.Add(existing);
        }
        else
        {
            existing.RestaurantRate = req.RestaurantRate;
            existing.DriverRate = req.DriverRate;
            existing.Comment = string.IsNullOrWhiteSpace(req.Comment) ? null : req.Comment.Trim();
            // Do not overwrite CreatedAtUtc on update.
        }

        await _db.SaveChangesAsync();

        // Backward compatibility + required event name
        await _hub.Clients.Group("admin").SendAsync("rating_added", new { orderId = o.Id, restaurantRate = existing.RestaurantRate, driverRate = existing.DriverRate, existing.CreatedAtUtc });
        await _hub.Clients.All.SendAsync("ratings_updated");

        await _notifications.CreateAndBroadcastAsync(NotificationUserType.Admin, null,
            "تقييم جديد", $"تم إضافة تقييم للطلب #{o.Id}", o.Id);

        return Ok(new { ok = true });
    }
}
