using AdminDashboard.Entities;
using AdminDashboard.Security;
using AdminDashboard.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;

namespace AdminDashboard.Controllers;

[ApiController]
[Route("api/public/register-fcm")]
public class FcmController : ControllerBase
{
    private readonly FcmService _fcm;
    private readonly IOptions<AppSecurityOptions> _opts;

    public FcmController(FcmService fcm, IOptions<AppSecurityOptions> opts)
    {
        _fcm = fcm;
        _opts = opts;
    }

    public record RegisterReq(int UserId, string Token, string? Platform);

    public record UnregisterReq(string Token);

    [HttpPost("customer")]
    public async Task<IActionResult> RegisterCustomer(RegisterReq req)
    {
        if (req.UserId <= 0 || string.IsNullOrWhiteSpace(req.Token))
            return BadRequest(new { error = "invalid" });

        await _fcm.RegisterTokenAsync(DeviceUserType.Customer, req.UserId, req.Token, req.Platform);
        return Ok(new { ok = true });
    }

    [HttpPost("customer/unregister")]
    public async Task<IActionResult> UnregisterCustomer([FromBody] UnregisterReq req)
    {
        if (string.IsNullOrWhiteSpace(req.Token)) return BadRequest(new { error = "invalid" });
        await _fcm.UnregisterTokenAsync(req.Token);
        return Ok(new { ok = true });
    }

    [HttpPost("driver")]
    public async Task<IActionResult> RegisterDriver([FromBody] RegisterReq req)
    {
        if (!Request.Headers.TryGetValue("X-DRIVER-TOKEN", out var token) || !DriverAuth.TryValidate(token!, _opts, out var driverId))
            return Unauthorized(new { error = "unauthorized" });

        if (string.IsNullOrWhiteSpace(req.Token))
            return BadRequest(new { error = "invalid" });

        await _fcm.RegisterTokenAsync(DeviceUserType.Driver, driverId, req.Token, req.Platform);
        return Ok(new { ok = true });
    }

    [HttpPost("driver/unregister")]
    public async Task<IActionResult> UnregisterDriver([FromBody] UnregisterReq req)
    {
        if (!Request.Headers.TryGetValue("X-DRIVER-TOKEN", out var token) || !DriverAuth.TryValidate(token!, _opts, out _))
            return Unauthorized(new { error = "unauthorized" });

        if (string.IsNullOrWhiteSpace(req.Token)) return BadRequest(new { error = "invalid" });
        await _fcm.UnregisterTokenAsync(req.Token);
        return Ok(new { ok = true });
    }

    /// <summary>
    /// Admin App (Flutter WebView) registers token here and subscribes to topic "admins".
    /// We store it under a single logical admin (UserId=1).
    /// Protected by X-ADMIN-KEY.
    /// </summary>
    [HttpPost("admin")]
    public async Task<IActionResult> RegisterAdmin([FromBody] RegisterReq req)
    {
        if (!Request.Headers.TryGetValue("X-ADMIN-KEY", out var key) || key != _opts.Value.AdminApiKey)
            return Unauthorized(new { error = "unauthorized" });

        if (string.IsNullOrWhiteSpace(req.Token))
            return BadRequest(new { error = "invalid" });

        await _fcm.RegisterTokenAsync(DeviceUserType.Admin, 1, req.Token, req.Platform);
        return Ok(new { ok = true });
    }
}

[ApiController]
[Route("api/admin/broadcast")]
[Authorize(Policy = "AdminOnly")]
public class BroadcastController : ControllerBase
{
    private readonly FcmService _fcm;
    public BroadcastController(FcmService fcm) => _fcm = fcm;

    public record BroadcastReq(string Target, string Title, string Body);

    [HttpPost]
    public async Task<IActionResult> Broadcast(BroadcastReq req)
    {
        var topic = req.Target?.Trim().ToLowerInvariant();
        if (topic != "customers" && topic != "drivers")
            return BadRequest(new { error = "target_must_be_customers_or_drivers" });

        await _fcm.SendToTopicAsync(topic, req.Title, req.Body);
        return Ok(new { ok = true });
    }
}