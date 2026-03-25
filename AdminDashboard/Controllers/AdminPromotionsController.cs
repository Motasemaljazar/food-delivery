using AdminDashboard.Data;
using AdminDashboard.Entities;
using AdminDashboard.Hubs;
using AdminDashboard.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace AdminDashboard.Controllers;

[ApiController]
[Route("api/admin/offers")]
[Authorize(Policy = "AdminOnly")]
public class AdminOffersController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IHubContext<NotifyHub> _hub;
    private readonly FcmService _fcm;

    public AdminOffersController(AppDbContext db, IHubContext<NotifyHub> hub, FcmService fcm)
    {
        _db = db;
        _hub = hub;
        _fcm = fcm;
    }

    [HttpGet]
    public async Task<IActionResult> List()
    {
        var list = await _db.Offers.AsNoTracking().OrderByDescending(o => o.Id).ToListAsync();
        var ids = list.Select(x => x.Id).ToList();
        var map = await _db.OfferProducts.AsNoTracking()
            .Where(op => ids.Contains(op.OfferId))
            .GroupBy(op => op.OfferId)
            .ToDictionaryAsync(g => g.Key, g => g.Select(x => x.ProductId).ToList());

        var catMap = await _db.OfferCategories.AsNoTracking()
            .Where(oc => ids.Contains(oc.OfferId))
            .GroupBy(oc => oc.OfferId)
            .ToDictionaryAsync(g => g.Key, g => g.Select(x => x.CategoryId).ToList());

        var shaped = list.Select(o => new
        {
            o.Id,
            o.Title,
            o.Description,
            o.ImageUrl,
            o.PriceBefore,
            o.PriceAfter,
            o.Code,
            o.StartsAtUtc,
            o.EndsAtUtc,
            o.IsActive,
            productIds = map.TryGetValue(o.Id, out var pids) ? pids : new List<int>(),
            categoryIds = catMap.TryGetValue(o.Id, out var cids) ? cids : new List<int>()
        });
        return Ok(new { offers = shaped });
    }

    public record UpsertOfferReq(
        int? Id,
        string Title,
        string? Description,
        string? ImageUrl,
        decimal? PriceBefore,
        decimal? PriceAfter,
        string? Code,
        DateTime? StartsAtUtc,
        DateTime? EndsAtUtc,
        bool IsActive,
        List<int>? ProductIds,
        List<int>? CategoryIds);

    [HttpPost]
    public async Task<IActionResult> Upsert(UpsertOfferReq req)
    {
        if (string.IsNullOrWhiteSpace(req.Title)) return BadRequest(new { error = "invalid_title" });

        var isNewOffer = req.Id is null;

        // Server-side de-duplication: prevent multiple identical offers due to double-click / network retries.
        // If the client sends Id=null but the newest offer has identical fields, return it instead of inserting.
        if (isNewOffer)
        {
            var t = req.Title.Trim();
            var d = string.IsNullOrWhiteSpace(req.Description) ? null : req.Description.Trim();
            var img = string.IsNullOrWhiteSpace(req.ImageUrl) ? null : req.ImageUrl.Trim();
            var newest = await _db.Offers.AsNoTracking().OrderByDescending(x => x.Id).FirstOrDefaultAsync();
            if (newest != null
                && string.Equals(newest.Title?.Trim(), t, StringComparison.OrdinalIgnoreCase)
                && string.Equals((newest.Description ?? "").Trim(), (d ?? "").Trim(), StringComparison.Ordinal)
                && string.Equals((newest.ImageUrl ?? "").Trim(), (img ?? "").Trim(), StringComparison.Ordinal)
                && newest.PriceBefore == req.PriceBefore
                && newest.PriceAfter == req.PriceAfter
                && string.Equals((newest.Code ?? "").Trim(), (req.Code ?? "").Trim(), StringComparison.Ordinal)
                && newest.StartsAtUtc == req.StartsAtUtc
                && newest.EndsAtUtc == req.EndsAtUtc
                && newest.IsActive == req.IsActive)
            {
                return Ok(new { offer = newest });
            }
        }

        Offer o;
        if (req.Id is null)
        {
            o = new Offer();
            _db.Offers.Add(o);
        }
        else
        {
            o = await _db.Offers.FirstOrDefaultAsync(x => x.Id == req.Id.Value) ?? new Offer();
            if (o.Id == 0) return NotFound(new { error = "not_found" });
        }

        o.Title = req.Title.Trim();
        o.Description = string.IsNullOrWhiteSpace(req.Description) ? null : req.Description.Trim();
        o.ImageUrl = string.IsNullOrWhiteSpace(req.ImageUrl) ? null : req.ImageUrl.Trim();
        o.PriceBefore = req.PriceBefore;
        o.PriceAfter = req.PriceAfter;
        o.Code = string.IsNullOrWhiteSpace(req.Code) ? null : req.Code.Trim();
        o.StartsAtUtc = req.StartsAtUtc;
        o.EndsAtUtc = req.EndsAtUtc;
        o.IsActive = req.IsActive;

        // Offer -> Products mapping
        var newIds = (req.ProductIds ?? new List<int>()).Distinct().Where(x => x > 0).ToList();

        // Offer -> Categories mapping
        var newCatIds = (req.CategoryIds ?? new List<int>()).Distinct().Where(x => x > 0).ToList();
        // Save offer first to get Id
        await _db.SaveChangesAsync();

        // Replace mapping
        var existing = await _db.OfferProducts.Where(x => x.OfferId == o.Id).ToListAsync();
        _db.OfferProducts.RemoveRange(existing);
        foreach (var pid in newIds)
        {
            _db.OfferProducts.Add(new OfferProduct { OfferId = o.Id, ProductId = pid });
        }

        var existingCats = await _db.OfferCategories.Where(x => x.OfferId == o.Id).ToListAsync();
        _db.OfferCategories.RemoveRange(existingCats);
        foreach (var cid in newCatIds)
        {
            _db.OfferCategories.Add(new OfferCategory { OfferId = o.Id, CategoryId = cid });
        }

        await _db.SaveChangesAsync();
        await _hub.Clients.Group("admin").SendAsync("offer_changed", new { id = o.Id });
        await _hub.Clients.All.SendAsync("offers_updated");

        // إشعار خارج التطبيق لجميع الزبائن عند إنشاء عرض جديد
        if (isNewOffer && o.IsActive)
        {
            var title = "عرض جديد 🎉";
            var desc = (o.Description ?? "").Trim();
            if (desc.Length > 100) desc = desc.Substring(0, 100) + "…";
            var body = o.Title.Trim();
            if (o.PriceAfter.HasValue && o.PriceAfter.Value > 0)
                body += $" — {o.PriceAfter.Value:N0} ل.س";
            if (!string.IsNullOrEmpty(desc)) body += "\n" + desc;
            var data = new Dictionary<string, string>
            {
                ["type"] = "new_offer",
                ["offerId"] = o.Id.ToString()
            };
            await _fcm.SendToTopicAsync("customers", title, body, data);
        }

        return Ok(new { offer = o });
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        var o = await _db.Offers.FirstOrDefaultAsync(x => x.Id == id);
        if (o == null) return NotFound(new { error = "not_found" });
        var ops = await _db.OfferProducts.Where(x => x.OfferId == id).ToListAsync();
        _db.OfferProducts.RemoveRange(ops);
        var ocs = await _db.OfferCategories.Where(x => x.OfferId == id).ToListAsync();
        _db.OfferCategories.RemoveRange(ocs);
        _db.Offers.Remove(o);
        await _db.SaveChangesAsync();
        await _hub.Clients.All.SendAsync("offers_updated");
        return Ok(new { ok = true });
    }
}
