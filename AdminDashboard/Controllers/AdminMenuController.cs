using AdminDashboard.Data;
using AdminDashboard.Entities;
using AdminDashboard.Hubs;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.SignalR;

namespace AdminDashboard.Controllers;

[ApiController]
[Route("api/admin/menu")]
[Authorize(Policy = "AdminOnly")]
public class AdminMenuController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IHubContext<NotifyHub> _hub;
    public AdminMenuController(AppDbContext db, IHubContext<NotifyHub> hub)
    {
        _db = db;
        _hub = hub;
    }

    private Task BroadcastMenuAsync() => _hub.Clients.All.SendAsync("menu_updated");
    private Task BroadcastCategoriesAsync() => _hub.Clients.All.SendAsync("categories_updated");

    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var cats = await _db.Categories.AsNoTracking().OrderBy(c => c.SortOrder).ToListAsync();
        var prods = await _db.Products.AsNoTracking().OrderBy(p => p.Id).ToListAsync();
        var imgs = await _db.ProductImages.AsNoTracking().OrderBy(i => i.SortOrder).ToListAsync();
        var variants = await _db.ProductVariants.AsNoTracking().OrderBy(v => v.SortOrder).ToListAsync();
        var addons = await _db.ProductAddons.AsNoTracking().OrderBy(a => a.SortOrder).ToListAsync();
        var now = DateTime.UtcNow;
        var offersRaw = await _db.Offers.AsNoTracking()
            .Where(o => o.IsActive && (o.StartsAtUtc == null || o.StartsAtUtc <= now) && (o.EndsAtUtc == null || o.EndsAtUtc >= now))
            .OrderBy(o => o.Id)
            .Select(o => new { o.Id, o.Title, o.PriceBefore, o.PriceAfter })
            .ToListAsync();
        var offerIds = offersRaw.Select(o => o.Id).ToList();
        var offerPrimaryProduct = offerIds.Count == 0
            ? new Dictionary<int, int>()
            : await _db.OfferProducts.AsNoTracking()
                .Where(op => offerIds.Contains(op.OfferId))
                .GroupBy(op => op.OfferId)
                .ToDictionaryAsync(g => g.Key, g => g.Select(x => x.ProductId).FirstOrDefault());
        var offers = offersRaw.Select(o => new
        {
            o.Id,
            o.Title,
            o.PriceBefore,
            o.PriceAfter,
            PrimaryProductId = offerPrimaryProduct.TryGetValue(o.Id, out var pid) && pid != 0 ? pid : (int?)null
        }).ToList();
        return Ok(new { categories = cats, products = prods, images = imgs, variants, addons, offers });
    }

    public record UpsertVariantReq(int? Id, int ProductId, string Name, decimal PriceDelta, bool IsActive, int SortOrder);

    [HttpPost("variant")]
    public async Task<IActionResult> UpsertVariant(UpsertVariantReq req)
    {
        var p = await _db.Products.FirstOrDefaultAsync(x => x.Id == req.ProductId);
        if (p == null) return BadRequest(new { error = "invalid_product" });
        ProductVariant v;
        if (req.Id is null)
        {
            v = new ProductVariant();
            _db.ProductVariants.Add(v);
        }
        else
        {
            v = await _db.ProductVariants.FirstOrDefaultAsync(x => x.Id == req.Id.Value) ?? new ProductVariant();
            if (v.Id == 0) return NotFound(new { error = "not_found" });
        }

        v.ProductId = req.ProductId;
        v.Name = req.Name;
        v.PriceDelta = req.PriceDelta;
        v.IsActive = req.IsActive;
        v.SortOrder = req.SortOrder;
        await _db.SaveChangesAsync();
        await BroadcastMenuAsync();
        return Ok(new
        {
            variant = new { v.Id, v.ProductId, v.Name, v.PriceDelta, v.IsActive, v.SortOrder }
        });
    }

    [HttpDelete("variant/{id:int}")]
    public async Task<IActionResult> DeleteVariant(int id)
    {
        var v = await _db.ProductVariants.FirstOrDefaultAsync(x => x.Id == id);
        if (v == null) return NotFound(new { error = "not_found" });
        _db.ProductVariants.Remove(v);
        await _db.SaveChangesAsync();
        await BroadcastMenuAsync();
        return Ok(new { ok = true });
    }

    public record UpsertAddonReq(int? Id, int ProductId, string Name, decimal Price, bool IsActive, int SortOrder);

    [HttpPost("addon")]
    public async Task<IActionResult> UpsertAddon(UpsertAddonReq req)
    {
        var p = await _db.Products.FirstOrDefaultAsync(x => x.Id == req.ProductId);
        if (p == null) return BadRequest(new { error = "invalid_product" });
        ProductAddon a;
        if (req.Id is null)
        {
            a = new ProductAddon();
            _db.ProductAddons.Add(a);
        }
        else
        {
            a = await _db.ProductAddons.FirstOrDefaultAsync(x => x.Id == req.Id.Value) ?? new ProductAddon();
            if (a.Id == 0) return NotFound(new { error = "not_found" });
        }

        a.ProductId = req.ProductId;
        a.Name = req.Name;
        a.Price = req.Price;
        a.IsActive = req.IsActive;
        a.SortOrder = req.SortOrder;
        await _db.SaveChangesAsync();
        await BroadcastMenuAsync();
        return Ok(new
        {
            addon = new { a.Id, a.ProductId, a.Name, a.Price, a.IsActive, a.SortOrder }
        });
    }

    [HttpDelete("addon/{id:int}")]
    public async Task<IActionResult> DeleteAddon(int id)
    {
        var a = await _db.ProductAddons.FirstOrDefaultAsync(x => x.Id == id);
        if (a == null) return NotFound(new { error = "not_found" });
        _db.ProductAddons.Remove(a);
        await _db.SaveChangesAsync();
        await BroadcastMenuAsync();
        return Ok(new { ok = true });
    }

    public record UpsertCategoryReq(int? Id, string Name, string? ImageUrl, bool IsActive, int SortOrder);

    [HttpPost("category")]
    public async Task<IActionResult> UpsertCategory(UpsertCategoryReq req)
    {
        Category c;
        if (req.Id is null)
        {
            c = new Category();
            _db.Categories.Add(c);
        }
        else
        {
            c = await _db.Categories.FirstOrDefaultAsync(x => x.Id == req.Id.Value) ?? new Category();
            if (c.Id == 0) return NotFound();
        }
        c.Name = req.Name;
        if (req.ImageUrl != null) c.ImageUrl = string.IsNullOrWhiteSpace(req.ImageUrl) ? null : req.ImageUrl.Trim();
        c.IsActive = req.IsActive;
        c.SortOrder = req.SortOrder;
        await _db.SaveChangesAsync();
        await BroadcastCategoriesAsync();
        await BroadcastMenuAsync();
        // Return a DTO (avoid EF navigation cycles)
        return Ok(new { id = c.Id, name = c.Name, imageUrl = c.ImageUrl, isActive = c.IsActive, sortOrder = c.SortOrder });
    }

    [HttpDelete("category/{id:int}")]
    public async Task<IActionResult> DeleteCategory(int id)
    {
        var c = await _db.Categories.FirstOrDefaultAsync(x => x.Id == id);
        if (c == null) return NotFound(new { error = "not_found" });
        _db.Categories.Remove(c);
        await _db.SaveChangesAsync();
        await BroadcastCategoriesAsync();
        await BroadcastMenuAsync();
        return Ok(new { ok = true });
    }

    public record UpsertProductReq(int? Id, int CategoryId, string Name, string? Description, decimal Price, bool IsActive, bool IsAvailable, List<string>? ImageUrls);

    [HttpPost("product")]
    public async Task<IActionResult> UpsertProduct(UpsertProductReq req)
    {
        var cat = await _db.Categories.FirstOrDefaultAsync(x => x.Id == req.CategoryId);
        if (cat == null) return BadRequest(new { error = "Invalid category" });

        Product p;
        if (req.Id is null)
        {
            p = new Product();
            _db.Products.Add(p);
        }
        else
        {
            p = await _db.Products.Include(x => x.Images).FirstOrDefaultAsync(x => x.Id == req.Id.Value) ?? new Product();
            if (p.Id == 0) return NotFound();
        }

        p.CategoryId = req.CategoryId;
        p.Name = req.Name;
        p.Description = req.Description;
        p.Price = req.Price;
        p.IsActive = req.IsActive;
        p.IsAvailable = req.IsAvailable;
        p.IsAvailable = req.IsAvailable;
        // Ensure Id exists for new products before images
        if (p.Id == 0)
            await _db.SaveChangesAsync();


        // Images (non-destructive):
        // - If ImageUrls provided, treat it as preferred ordering.
        // - Add missing urls.
        // - Keep existing urls not mentioned (append after provided order).
        // This ensures "رفع صور جديدة لا يحذف القديمة".
        if (req.ImageUrls != null)
        {
            var urls = req.ImageUrls
                .Where(u => !string.IsNullOrWhiteSpace(u))
                .Select(u => u.Trim())
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();

            var existing = await _db.ProductImages.Where(i => i.ProductId == p.Id).ToListAsync();
            var byUrl = existing
                .Where(i => !string.IsNullOrWhiteSpace(i.Url))
                .GroupBy(i => i.Url, StringComparer.OrdinalIgnoreCase)
                .ToDictionary(g => g.Key, g => g.First(), StringComparer.OrdinalIgnoreCase);

            var idx = 0;
            foreach (var url in urls)
            {
                if (byUrl.TryGetValue(url, out var img))
                {
                    img.SortOrder = idx++;
                }
                else
                {
                    _db.ProductImages.Add(new ProductImage { ProductId = p.Id, Url = url, SortOrder = idx++ });
                }
            }

            // Append any existing images not included in request
            foreach (var img in existing.OrderBy(i => i.SortOrder).ThenBy(i => i.Id))
            {
                if (!urls.Contains(img.Url ?? "", StringComparer.OrdinalIgnoreCase))
                {
                    img.SortOrder = idx++;
                }
            }
        }

        await _db.SaveChangesAsync();
        await BroadcastMenuAsync();
        // Return DTO (avoid JSON cycles Category <-> Products)
        var images = await _db.ProductImages.AsNoTracking()
            .Where(i => i.ProductId == p.Id)
            .OrderBy(i => i.SortOrder)
            .Select(i => new { i.Id, i.Url, i.SortOrder })
            .ToListAsync();

        // Backward-compatible response: admin JS expects `saved.id`.
        return Ok(new
        {
            id = p.Id,
            categoryId = p.CategoryId,
            name = p.Name,
            description = p.Description,
            price = p.Price,
            isActive = p.IsActive,
            images
        });
    }

    [HttpDelete("product/{id:int}")]
    public async Task<IActionResult> DeleteProduct(int id)
    {
        var p = await _db.Products.FirstOrDefaultAsync(x => x.Id == id);
        if (p == null) return NotFound(new { error = "not_found" });
        _db.Products.Remove(p);
        await _db.SaveChangesAsync();
        await BroadcastMenuAsync();
        return Ok(new { ok = true });
    }
}
