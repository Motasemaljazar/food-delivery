using AdminDashboard.Data;
using AdminDashboard.Entities;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AdminDashboard.Controllers;

[ApiController]
[Route("api/admin/discounts")]
[Authorize(Policy = "AdminOnly")]
public class AdminDiscountsController : ControllerBase
{
    private readonly AppDbContext _db;

    public AdminDiscountsController(AppDbContext db)
    {
        _db = db;
    }

    [HttpGet]
    public async Task<IActionResult> List([FromQuery] bool onlyActive = false)
    {
        var now = DateTime.UtcNow;
        var q = _db.Discounts.AsNoTracking().AsQueryable();
        if (onlyActive)
            q = q.Where(d => d.IsActive
                             && (d.StartsAtUtc == null || d.StartsAtUtc <= now)
                             && (d.EndsAtUtc == null || d.EndsAtUtc >= now));

        var items = await q.OrderByDescending(d => d.IsActive)
            .ThenByDescending(d => d.Id)
            .ToListAsync();

        return Ok(new { items });
    }

    public record UpsertDiscountRequest(
        int? Id,
        string Title,
        DiscountTargetType TargetType,
        int? TargetId,
        DiscountValueType ValueType,
        decimal? Percent,
        decimal? Amount,
        decimal? MinOrderAmount,
        bool IsActive,
        DateTime? StartsAtUtc,
        DateTime? EndsAtUtc,
        string? BadgeText
    );

    [HttpPost]
    public async Task<IActionResult> Upsert(UpsertDiscountRequest req)
    {
        // SRDS: Simple automatic discounts only (no coupons):
        // - Only Product/Category
        // - Only Percent
        if (req.TargetType == DiscountTargetType.Cart)
            return BadRequest(new { error = "cart_discount_not_supported" });

        req = req with { ValueType = DiscountValueType.Percent, Amount = null, MinOrderAmount = null };

        // Basic validation
        var title = (req.Title ?? "").Trim();
        if (string.IsNullOrWhiteSpace(title))
            title = "خصم";

        if (req.TargetId == null)
            return BadRequest(new { error = "target_required" });

        var pcent = req.Percent ?? 0;
        if (pcent <= 0 || pcent > 100) return BadRequest(new { error = "percent_invalid" });

        Discount ent;
        if (req.Id != null && req.Id.Value > 0)
        {
            ent = await _db.Discounts.FirstOrDefaultAsync(x => x.Id == req.Id.Value) ?? new Discount();
            if (ent.Id == 0) _db.Discounts.Add(ent);
        }
        else
        {
            ent = new Discount();
            _db.Discounts.Add(ent);
        }

        // Auto title/badge to keep admin simple
        ent.Title = string.IsNullOrWhiteSpace(title) ? "خصم" : title;
        ent.TargetType = req.TargetType;
        ent.TargetId = req.TargetId;
        ent.ValueType = DiscountValueType.Percent;
        ent.Percent = pcent;
        ent.Amount = null;
        ent.MinOrderAmount = null;
        ent.IsActive = req.IsActive;
        ent.StartsAtUtc = req.StartsAtUtc;
        ent.EndsAtUtc = req.EndsAtUtc;
        ent.BadgeText = $"خصم {Math.Round(pcent, 0)}%";

        await _db.SaveChangesAsync();
        return Ok(new { ok = true, id = ent.Id });
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        var ent = await _db.Discounts.FirstOrDefaultAsync(x => x.Id == id);
        if (ent == null) return NotFound();
        _db.Discounts.Remove(ent);
        await _db.SaveChangesAsync();
        return Ok(new { ok = true });
    }
}