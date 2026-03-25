using AdminDashboard.Data;
using AdminDashboard.Entities;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;

namespace AdminDashboard.Controllers;

[ApiController]
[Route("api/public")]
public class PublicController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly ILogger<PublicController> _logger;

    public PublicController(AppDbContext db, ILogger<PublicController> logger)
    {
        _db = db;
        _logger = logger;
    }

    // Backwards-compatible endpoint
    [HttpGet("settings")]
    public Task<IActionResult> GetSettings() => GetAppConfig();

    private string GetPublicBaseUrl()
    {
        // Some hosting setups terminate TLS at a reverse proxy and forward requests to Kestrel over HTTP.
        // In such case, Request.Scheme may be "http" even though the public URL is "https".
        // Flutter apps (especially Android 9+ and Flutter Web) will then refuse to load images due to
        // mixed-content/cleartext restrictions. We defensively read forwarded headers.
        string FirstHeader(string name)
        {
            var raw = Request.Headers[name].ToString();
            if (string.IsNullOrWhiteSpace(raw)) return "";
            // Proxies may send comma-separated values.
            return raw.Split(',').FirstOrDefault()?.Trim() ?? "";
        }

        var proto = FirstHeader("X-Forwarded-Proto");
        var host = FirstHeader("X-Forwarded-Host");

        var scheme = !string.IsNullOrWhiteSpace(proto) ? proto : Request.Scheme;
        var finalHost = !string.IsNullOrWhiteSpace(host) ? host : Request.Host.Value;

        // Fallback if somehow empty
        if (string.IsNullOrWhiteSpace(finalHost)) finalHost = Request.Host.ToString();
        if (string.IsNullOrWhiteSpace(scheme)) scheme = "https";

        return $"{scheme}://{finalHost}";
    }

    [HttpGet("app-config")]
    public async Task<IActionResult> GetAppConfig()
    {
        var s = await _db.RestaurantSettings.AsNoTracking().FirstOrDefaultAsync();
        var baseUrl = GetPublicBaseUrl();

        static string? Abs(string baseUrl, string? url)
        {
            if (string.IsNullOrWhiteSpace(url)) return null;
            if (url.StartsWith("http://") || url.StartsWith("https://")) return url;
            if (!url.StartsWith("/")) url = "/" + url;
            // cache-bust so branding updates show immediately in Flutter Web.
            var v = DateTime.UtcNow.Ticks;
            return baseUrl + url + $"?v={v}";
        }

        if (s == null)
        {
            return Ok(new
            {
                restaurantName = "",
                logoUrl = (string?)null,
                primaryColor = "#D32F2F",
                secondaryColor = "#111827",
                isManuallyClosed = false,
                closedMessage = "المطعم مغلق حالياً",
                closedScreenImageUrl = (string?)null,
                closedBackgroundUrl = (string?)null,
                restaurantLat = 0,
                restaurantLng = 0,
                supportPhone = "",
                supportWhatsApp = "",
                socialLinks = new { whatsapp = "", facebook = (string?)null, instagram = (string?)null, telegram = (string?)null },
                routingProfile = "driving",
                settingsVersion = DateTime.UtcNow.ToUniversalTime().ToString("O"),
            });
        }

        var settingsVersion = s.UpdatedAtUtc.ToUniversalTime().ToString("O");

        List<string> homeBanners = new();
        try
        {
            if (!string.IsNullOrWhiteSpace(s.HomeBannersJson))
            {
                var arr = JsonSerializer.Deserialize<List<string>>(s.HomeBannersJson!) ?? new List<string>();
                homeBanners = arr
                    .Where(x => !string.IsNullOrWhiteSpace(x))
                    .Select(x => Abs(baseUrl, x)!)
                    .Where(x => x != null)
                    .ToList();
            }
        }
        catch
        {
            homeBanners = new();
        }

        return Ok(new
        {
            restaurantName = s.RestaurantName,
            logoUrl = Abs(baseUrl, s.LogoUrl),
            primaryColor = s.PrimaryColorHex,
            secondaryColor = s.SecondaryColorHex,
            supportPhone = s.SupportPhone,
            supportWhatsApp = s.SupportWhatsApp,
            socialLinks = new
            {
                whatsapp = s.SupportWhatsApp,
                facebook = s.FacebookUrl,
                instagram = s.InstagramUrl,
                telegram = s.TelegramUrl
            },
            isManuallyClosed = s.IsManuallyClosed,
            closedMessage = s.ClosedMessage,
            closedScreenImageUrl = Abs(baseUrl, s.ClosedScreenImageUrl),
            // Alias required by some UI screens
            closedBackgroundUrl = Abs(baseUrl, s.ClosedScreenImageUrl),
            restaurantLat = s.RestaurantLat,
            restaurantLng = s.RestaurantLng,
            routingProfile = s.RoutingProfile,
            homeBanners,
            settingsVersion
        });
    }

    [HttpGet("offers/{offerId:int}/items")]
    public async Task<IActionResult> GetOfferItems(int offerId)
    {
        var baseUrl = GetPublicBaseUrl();
        static string? Abs(string baseUrl, string? url)
        {
            if (string.IsNullOrWhiteSpace(url)) return null;
            if (url.StartsWith("http://") || url.StartsWith("https://")) return url;
            if (!url.StartsWith("/")) url = "/" + url;
            var v = DateTime.UtcNow.Ticks;
            return baseUrl + url + $"?v={v}";
        }

        var productIds = await _db.OfferProducts.AsNoTracking()
            .Where(x => x.OfferId == offerId)
            .Select(x => x.ProductId)
            .ToListAsync();

        if (productIds.Count == 0)
        {
            return Ok(new { items = Array.Empty<object>() });
        }

        // Materialize products, then shape with related data.
        var products = await _db.Products.AsNoTracking()
            .Where(p => productIds.Contains(p.Id) && p.IsActive && p.IsAvailable)
            .Select(p => new { p.Id, p.Name, p.Description, p.Price, p.CategoryId })
            .ToListAsync();

        var images = await _db.ProductImages.AsNoTracking()
            .Where(i => productIds.Contains(i.ProductId))
            .OrderByDescending(i => i.IsPrimary)
            .ThenBy(i => i.SortOrder)
            .ThenBy(i => i.Id)
            .ToListAsync();

        var variants = await _db.ProductVariants.AsNoTracking()
            .Where(v => productIds.Contains(v.ProductId) && v.IsActive)
            .OrderBy(v => v.SortOrder).ThenBy(v => v.Id)
            .ToListAsync();

        var addons = await _db.ProductAddons.AsNoTracking()
            .Where(a => productIds.Contains(a.ProductId) && a.IsActive)
            .OrderBy(a => a.SortOrder).ThenBy(a => a.Id)
            .ToListAsync();

        var shaped = products
            .OrderBy(p => productIds.IndexOf(p.Id))
            .Select(p => new
            {
                id = p.Id,
                name = p.Name,
                description = p.Description,
                price = p.Price,
                categoryId = p.CategoryId,
                imageUrl = Abs(baseUrl, images.FirstOrDefault(i => i.ProductId == p.Id)?.Url),
                images = images.Where(i => i.ProductId == p.Id).Select(i => new { i.Id, url = Abs(baseUrl, i.Url), i.SortOrder, i.IsPrimary }),
                variants = variants.Where(v => v.ProductId == p.Id).Select(v => new { v.Id, v.Name, v.PriceDelta, v.SortOrder }),
                addons = addons.Where(a => a.ProductId == p.Id).Select(a => new { a.Id, a.Name, a.Price, a.SortOrder }),
            });

        return Ok(new { items = shaped });
    }

    [HttpGet("menu")]
    public async Task<IActionResult> GetMenu()
    {
        try
        {
            var baseUrl = GetPublicBaseUrl();
            static string? Abs(string baseUrl, string? url)
            {
                if (string.IsNullOrWhiteSpace(url)) return null;
                if (url.StartsWith("http://") || url.StartsWith("https://")) return url;
                if (!url.StartsWith("/")) url = "/" + url;
                var v = DateTime.UtcNow.Ticks;
                return baseUrl + url + $"?v={v}";
            }

            var s = await _db.RestaurantSettings.AsNoTracking().FirstOrDefaultAsync();

            var now = DateTime.UtcNow;

            var discounts = await _db.Discounts.AsNoTracking()
                .Where(d => d.IsActive && (d.StartsAtUtc == null || d.StartsAtUtc <= now) && (d.EndsAtUtc == null || d.EndsAtUtc >= now))
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

            (decimal finalPrice, string? badgeText, decimal? percent) BestDiscountForProduct(int productId, int categoryId, decimal original)
            {
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

			// IMPORTANT: do NOT call local functions (Abs) inside EF Core expressions.
			// We first materialize, then shape the JSON in-memory.
			var offersRaw = await _db.Offers.AsNoTracking()
				.Where(o => o.IsActive
						&& (o.StartsAtUtc == null || o.StartsAtUtc <= now)
						&& (o.EndsAtUtc == null || o.EndsAtUtc >= now))
				.OrderByDescending(o => o.StartsAtUtc ?? DateTime.MinValue)
				.ThenByDescending(o => o.Id)
				.Select(o => new
				{
					o.Id,
					o.Title,
					o.Description,
					o.ImageUrl,
					o.PriceBefore,
					o.PriceAfter,
					o.Code,
					o.StartsAtUtc,
					o.EndsAtUtc
				})
				.ToListAsync();

			// Defensive de-dup (in case DB contains duplicated rows).
			var offers = offersRaw
				.GroupBy(x => x.Id)
				.Select(g => g.OrderByDescending(x => x.Id).First())
				.ToList();

			var offerIds = offers.Select(x => x.Id).ToList();
			var offerProductsMap = offerIds.Count == 0
				? new Dictionary<int, List<int>>()
				: await _db.OfferProducts.AsNoTracking()
					.Where(op => offerIds.Contains(op.OfferId))
					.GroupBy(op => op.OfferId)
					.ToDictionaryAsync(g => g.Key, g => g.Select(x => x.ProductId).ToList());

			var offerCategoriesMap = offerIds.Count == 0
				? new Dictionary<int, List<int>>()
				: await _db.OfferCategories.AsNoTracking()
					.Where(oc => offerIds.Contains(oc.OfferId))
					.GroupBy(oc => oc.OfferId)
					.ToDictionaryAsync(g => g.Key, g => g.Select(x => x.CategoryId).ToList());

			var offersShaped = offers.Select(o =>
			{
				var urlList = string.IsNullOrWhiteSpace(o.ImageUrl) ? Array.Empty<string>() : new[] { o.ImageUrl };
				var urls = urlList
					.Select((u, i) => new { id = i, url = Abs(baseUrl, u), sortOrder = i, isPrimary = i == 0 })
					.ToList<object>();
				return new
				{
					o.Id,
					o.Title,
					o.Description,
					imageUrl = Abs(baseUrl, o.ImageUrl),
					images = urls,
					priceBefore = o.PriceBefore,
					priceAfter = o.PriceAfter,
					code = o.Code,
					o.StartsAtUtc,
					o.EndsAtUtc,
					linkedProductIds = offerProductsMap.ContainsKey(o.Id) ? offerProductsMap[o.Id] : new List<int>(),
					primaryProductId = (offerProductsMap.ContainsKey(o.Id) && offerProductsMap[o.Id].Count > 0)
						? offerProductsMap[o.Id][0]
						: (int?)null,
					linkedCategoryIds = offerCategoriesMap.ContainsKey(o.Id) ? offerCategoriesMap[o.Id] : new List<int>(),
					primaryCategoryId = (offerCategoriesMap.ContainsKey(o.Id) && offerCategoriesMap[o.Id].Count > 0)
						? offerCategoriesMap[o.Id][0]
						: (int?)null,
				};
			}).ToList();

			// Popular items: Top sold by quantity (fallback to newest products if no orders yet)
			var popularIds = await _db.OrderItems.AsNoTracking()
				.Where(i => i.ProductId > 0)
				.GroupBy(i => i.ProductId)
				.Select(g => new { ProductId = g.Key, Qty = g.Sum(x => x.Quantity) })
				.OrderByDescending(x => x.Qty)
				.ThenByDescending(x => x.ProductId)
				.Take(12)
				.Select(x => x.ProductId)
				.ToListAsync();

			var popularProductsRaw = popularIds.Count == 0
				? await _db.Products.AsNoTracking()
					.Where(p => p.IsActive && p.IsAvailable)
					.OrderByDescending(p => p.Id)
					.Take(12)
					.Select(p => new { p.Id, p.Name, p.Description, p.Price, p.CategoryId })
					.ToListAsync()
				: await _db.Products.AsNoTracking()
					.Where(p => popularIds.Contains(p.Id) && p.IsActive && p.IsAvailable)
					.Select(p => new { p.Id, p.Name, p.Description, p.Price, p.CategoryId })
					.ToListAsync();

			var popularImages = await _db.ProductImages.AsNoTracking()
				.Where(i => popularProductsRaw.Select(p => p.Id).Contains(i.ProductId))
				.ToListAsync();

			var popularProducts = popularProductsRaw
    .OrderBy(p => popularIds.Count == 0 ? 0 : popularIds.IndexOf(p.Id))
    .ThenByDescending(p => p.Id)
    .Select(p =>
    {
        var d = BestDiscountForProduct(p.Id, p.CategoryId, p.Price);
        return new
        {
            p.Id,
            p.Name,
            p.Description,
            price = d.finalPrice,
            originalPrice = p.Price,
            discountBadge = d.badgeText,
            discountPercent = d.percent,
            p.CategoryId,
            imageUrl = Abs(baseUrl,
                popularImages
                    .Where(x => x.ProductId == p.Id)
                    .OrderByDescending(x => x.IsPrimary)
                    .ThenBy(x => x.SortOrder)
                    .ThenBy(x => x.Id)
                    .FirstOrDefault()?.Url)
        };
    }).ToList();

            var categories = await _db.Categories
                .AsNoTracking()
                .Where(c => c.IsActive)
                .OrderBy(c => c.SortOrder)
                .Include(c => c.Products.Where(p => p.IsActive))
                    .ThenInclude(p => p.Images)
                .Include(c => c.Products.Where(p => p.IsActive))
                    .ThenInclude(p => p.Variants)
                .Include(c => c.Products.Where(p => p.IsActive))
                    .ThenInclude(p => p.Addons)
                .ToListAsync();

            var cats = categories.Select(c => new
            {
                c.Id,
                c.Name,
                imageUrl = Abs(baseUrl, c.ImageUrl),
                products = c.Products
        .Where(p => p.IsActive && p.IsAvailable)
        .OrderBy(p => p.Id)
        .Select(p =>
        {
            var d = BestDiscountForProduct(p.Id, p.CategoryId, p.Price);
            return new
            {
                p.Id,
                p.Name,
                p.Description,
                price = d.finalPrice,
                originalPrice = p.Price,
                discountBadge = d.badgeText,
                discountPercent = d.percent,
                images = (p.Images ?? new()).OrderBy(i => i.SortOrder).ThenBy(i => i.Id)
                    .Select(i => new { i.Id, url = Abs(baseUrl, i.Url), i.SortOrder, i.IsPrimary }),
                variants = (p.Variants ?? new()).Where(v => v.IsActive).OrderBy(v => v.SortOrder).ThenBy(v => v.Id)
                    .Select(v => new { v.Id, v.Name, v.PriceDelta }),
                addons = (p.Addons ?? new()).Where(a => a.IsActive).OrderBy(a => a.SortOrder).ThenBy(a => a.Id)
                    .Select(a => new { a.Id, a.Name, a.Price })
            };
        }).ToList()
            });


            return Ok(new
            {
                settings = new
                {
                    restaurantName = s?.RestaurantName ?? "",
                    logoUrl = Abs(baseUrl, s?.LogoUrl),
                    primaryColor = s?.PrimaryColorHex ?? "#D32F2F",
                    secondaryColor = s?.SecondaryColorHex ?? "#111827",
                    isManuallyClosed = s?.IsManuallyClosed ?? false,
                    closedMessage = s?.ClosedMessage ?? "المطعم مغلق حالياً",
                    closedScreenImageUrl = Abs(baseUrl, s?.ClosedScreenImageUrl)
                },

                offers = offersShaped,
                categories = cats,
                popularProducts
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to load menu");
            // Always return JSON (required by the user)
            return Ok(new { settings = new { }, offers = Array.Empty<object>(), categories = Array.Empty<object>(), error = "menu_failed" });
        }
    }

    /// <summary>
    /// تقدير رسوم التوصيل حسب الموقع — يستدعيه تطبيق الزبون بعد تعيين الموقع ليعرض السعر قبل إرسال الطلب.
    /// </summary>
    [HttpGet("delivery-estimate")]
    public async Task<IActionResult> GetDeliveryEstimate([FromQuery] double lat, [FromQuery] double lng)
    {
        var settings = await _db.RestaurantSettings.AsNoTracking().FirstOrDefaultAsync()
            ?? new RestaurantSettings
            {
                RestaurantLat = 0,
                RestaurantLng = 0,
                DeliveryFeeType = DeliveryFeeType.Fixed,
                DeliveryFeeValue = 0,
                DeliveryFeePerKm = 0
            };

        double distanceKm = 0;
        if (settings.RestaurantLat != 0 || settings.RestaurantLng != 0)
            distanceKm = HaversineKm(settings.RestaurantLat, settings.RestaurantLng, lat, lng);

        decimal deliveryFee;
        // نفس منطق إنشاء الطلب: توصيل مجاني ضمن مسافة FreeDeliveryMaxKm إن كانت مفعَّلة.
        if (settings.FreeDeliveryMaxKm > 0 && distanceKm > 0 && distanceKm <= settings.FreeDeliveryMaxKm)
        {
            deliveryFee = 0;
        }
        else if (settings.DeliveryFeePerKm > 0 && distanceKm >= 0)
        {
            deliveryFee = Math.Round((decimal)distanceKm * settings.DeliveryFeePerKm, 2);
        }
        else
        {
            deliveryFee = settings.DeliveryFeeType == DeliveryFeeType.Fixed ? settings.DeliveryFeeValue : settings.DeliveryFeeValue;
        }

        return Ok(new
        {
            deliveryFee = (double)deliveryFee,
            deliveryDistanceKm = Math.Round(distanceKm, 3)
        });
    }

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
}
