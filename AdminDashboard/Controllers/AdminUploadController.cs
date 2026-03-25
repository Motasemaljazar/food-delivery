using AdminDashboard.Data;
using AdminDashboard.Entities;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AdminDashboard.Controllers;

[ApiController]
[Route("api/admin/upload")]
[Authorize(Policy = "AdminOnly")]
public class AdminUploadController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IWebHostEnvironment _env;

    public AdminUploadController(AppDbContext db, IWebHostEnvironment env)
    {
        _db = db;
        _env = env;
    }

    private string ResolveWebRoot()
    {
        // Some hosts may not set WebRootPath if wwwroot is missing at startup.
        // We fallback to ContentRoot/wwwroot to guarantee uploads are saved where StaticFiles middleware serves from.
        var webRoot = _env.WebRootPath;
        if (!string.IsNullOrWhiteSpace(webRoot))
        {
            Directory.CreateDirectory(webRoot);
            return webRoot;
        }

        var fallback = Path.Combine(_env.ContentRootPath, "wwwroot");
        Directory.CreateDirectory(fallback);
        return fallback;
    }


    [HttpPost("asset")]
    public async Task<IActionResult> UploadAsset([FromQuery] string kind, [FromForm] IFormFile file)
    {
        if (file == null || file.Length == 0) return BadRequest(new { error = "empty_file" });

        kind = (kind ?? "asset").Trim().ToLowerInvariant();

        // NOTE:
        // We keep historical/legacy folders for backward compatibility.
        // Some earlier builds stored offer images under /uploads/offers/* (not /uploads/assets/offers/*).
        // If the DB contains such URLs, the customer app will request /uploads/offers/... .
        // So for kind=offers we store in /uploads/offers/ to guarantee the URL always resolves.
        // Everything else stays in /uploads/assets/{kind}.
        var folderRel = kind == "offers"
            ? "uploads/offers"
            : $"uploads/assets/{kind}";
        var folderAbs = Path.Combine(ResolveWebRoot(), folderRel);
        Directory.CreateDirectory(folderAbs);

        var ext = Path.GetExtension(file.FileName);
        var name = $"{DateTime.UtcNow:yyyyMMddHHmmssfff}_{Guid.NewGuid():N}{ext}";
        var abs = Path.Combine(folderAbs, name);

        await using (var fs = System.IO.File.Create(abs))
        {
            await file.CopyToAsync(fs);
        }

        var url = "/" + folderRel + "/" + name;
        return Ok(new { url });
    }

    [HttpPost("product-images/{productId:int}")]
    public async Task<IActionResult> UploadProductImages(int productId, [FromForm] List<IFormFile>? files)
    {
        // Load product with images so we can compute sort order + primary logic safely.
        var product = await _db.Products
            .Include(p => p.Images)
            .FirstOrDefaultAsync(p => p.Id == productId);

        if (product == null)
            return NotFound(new { error = "product_not_found" });

        // Some browsers/frameworks may send multi-files under different form keys (files/files[]/file etc.).
        // We collect from BOTH Request.Form.Files and the bound "files" list to be safe.
        var allFiles = new List<IFormFile>();

        if (Request.Form.Files != null && Request.Form.Files.Count > 0)
            allFiles.AddRange(Request.Form.Files);

        if (files != null && files.Count > 0)
            allFiles.AddRange(files);

        // Remove duplicates (sometimes both sources contain the same references)
        allFiles = allFiles
            .Where(f => f != null && f.Length > 0)
            .Distinct()
            .ToList();

        if (allFiles.Count == 0)
            return BadRequest(new { error = "no_files" });

        var folderRel = $"uploads/products/{productId}";
        var folderAbs = Path.Combine(ResolveWebRoot(), folderRel);
        Directory.CreateDirectory(folderAbs);

        int nextSort =
            product.Images.Count == 0
                ? 0
                : product.Images.Max(i => i.SortOrder) + 1;

        bool setPrimaryNext = !product.Images.Any(i => i.IsPrimary);

        // Create entities first, then save, then return IDs.
        var createdEntities = new List<ProductImage>();

        foreach (var file in allFiles)
        {
            var ext = Path.GetExtension(file.FileName);
            var name = $"{DateTime.UtcNow:yyyyMMddHHmmssfff}_{Guid.NewGuid():N}{ext}";
            var abs = Path.Combine(folderAbs, name);

            await using (var fs = System.IO.File.Create(abs))
            {
                await file.CopyToAsync(fs);
            }

            var url = "/" + folderRel + "/" + name;

            var img = new ProductImage
            {
                ProductId = productId,
                Url = url,
                SortOrder = nextSort++,
                IsPrimary = setPrimaryNext
            };

            if (setPrimaryNext) setPrimaryNext = false;

            _db.ProductImages.Add(img);
            createdEntities.Add(img);
        }

        await _db.SaveChangesAsync();

        var created = createdEntities
            .OrderBy(i => i.SortOrder)
            .ThenBy(i => i.Id)
            .Select(i => new { i.Id, i.Url, i.SortOrder, i.IsPrimary })
            .ToList();

        return Ok(new { images = created });
    }

    [HttpDelete("product-images/{productId:int}")]
    public async Task<IActionResult> ClearProductImages(int productId)
    {
        var imgs = await _db.ProductImages.Where(i => i.ProductId == productId).ToListAsync();
        _db.ProductImages.RemoveRange(imgs);
        await _db.SaveChangesAsync();

        // Best-effort delete physical files
        try
        {
            var folderAbs = Path.Combine(ResolveWebRoot(), "uploads", "products", productId.ToString());
            if (Directory.Exists(folderAbs))
                Directory.Delete(folderAbs, recursive: true);
        }
        catch
        {
            // ignore
        }

        return Ok(new { ok = true });
    }

    [HttpDelete("product-image/{imageId:int}")]
    public async Task<IActionResult> DeleteProductImage(int imageId)
    {
        var img = await _db.ProductImages.FirstOrDefaultAsync(i => i.Id == imageId);
        if (img == null) return NotFound(new { error = "not_found" });

        // Best-effort delete physical file if it's inside wwwroot
        try
        {
            if (!string.IsNullOrWhiteSpace(img.Url) && img.Url.StartsWith("/"))
            {
                var rel = img.Url.TrimStart('/').Replace('/', Path.DirectorySeparatorChar);
                var abs = Path.Combine(ResolveWebRoot(), rel);
                if (System.IO.File.Exists(abs))
                    System.IO.File.Delete(abs);
            }
        }
        catch
        {
            // ignore
        }

        _db.ProductImages.Remove(img);
        await _db.SaveChangesAsync();
        return Ok(new { ok = true });
    }

    // Set a specific image as the primary image for its product.
    [HttpPost("product-image/{imageId:int}/primary")]
    public async Task<IActionResult> SetPrimary(int imageId)
    {
        var img = await _db.ProductImages.FirstOrDefaultAsync(i => i.Id == imageId);
        if (img == null) return NotFound(new { error = "not_found" });

        var all = await _db.ProductImages.Where(i => i.ProductId == img.ProductId).ToListAsync();
        foreach (var i in all) i.IsPrimary = i.Id == img.Id;

        await _db.SaveChangesAsync();
        return Ok(new { ok = true });
    }

    // Move an image up/down within the product gallery (reorders SortOrder).
    [HttpPost("product-image/{imageId:int}/move")]
    public async Task<IActionResult> MoveImage(int imageId, [FromQuery] string dir)
    {
        dir = (dir ?? "").Trim().ToLowerInvariant();
        if (dir != "up" && dir != "down") return BadRequest(new { error = "invalid_dir" });

        var img = await _db.ProductImages.FirstOrDefaultAsync(i => i.Id == imageId);
        if (img == null) return NotFound(new { error = "not_found" });

        var imgs = await _db.ProductImages
            .Where(i => i.ProductId == img.ProductId)
            .OrderBy(i => i.SortOrder)
            .ThenBy(i => i.Id)
            .ToListAsync();

        var idx = imgs.FindIndex(i => i.Id == imageId);
        if (idx < 0) return NotFound(new { error = "not_found" });

        var swapWith = dir == "up" ? idx - 1 : idx + 1;
        if (swapWith < 0 || swapWith >= imgs.Count) return Ok(new { ok = true });

        var a = imgs[idx];
        var b = imgs[swapWith];

        (a.SortOrder, b.SortOrder) = (b.SortOrder, a.SortOrder);

        await _db.SaveChangesAsync();
        return Ok(new { ok = true });
    }
}
