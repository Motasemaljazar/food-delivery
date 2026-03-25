using AdminDashboard.Entities;
using AdminDashboard.Security;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;

namespace AdminDashboard.Data;

public static class DbSeeder
{
    public static async Task SeedAsync(AppDbContext db, bool isDevelopment, IConfiguration? config = null)
    {
        // 1) Admin user (cookie auth)
        // هذا الحساب للتشغيل المحلي فقط. في Production يجب تحديد حساب مسؤول أولي عبر الإعدادات أو إنشاءه من DB.
        if (!await db.AdminUsers.AnyAsync())
        {
            if (isDevelopment)
            {
                var (hash, salt) = AdminPassword.HashPassword("admin123");
                db.AdminUsers.Add(new AdminUser
                {
                    Email = "admin",
                    PasswordHash = hash,
                    PasswordSalt = salt
                });
            }
            else
            {
                var email = config?["InitialAdmin:Email"];
                var pass = config?["InitialAdmin:Password"];
                if (!string.IsNullOrWhiteSpace(email) && !string.IsNullOrWhiteSpace(pass))
                {
                    var (hash, salt) = AdminPassword.HashPassword(pass);
                    db.AdminUsers.Add(new AdminUser
                    {
                        Email = email.Trim(),
                        PasswordHash = hash,
                        PasswordSalt = salt
                    });
                }
                else
                {
                    throw new InvalidOperationException(
                        "No admin user found. In Production, set InitialAdmin:Email and InitialAdmin:Password in appsettings.Production.json (or env vars) for the first run.");
                }
            }
        }

        // 2) Restaurant settings (minimal defaults)
        // لا نضع موقع حقيقي افتراضياً، ولا نفعّل استقبال الطلبات إلا بعد ضبط الإعدادات.
        if (!await db.RestaurantSettings.AnyAsync())
        {
            db.RestaurantSettings.Add(new RestaurantSettings
            {
                RestaurantName = "المطعم",
                PrimaryColorHex = "#D32F2F",
                SecondaryColorHex = "#111827",
                OffersColorHex = "#E11D48",
                WelcomeText = "أهلاً بك",
                WorkHours = "",
                RestaurantLat = 0,
                RestaurantLng = 0,
                IsManuallyClosed = false,
                ClosedMessage = "المطعم مغلق حالياً",
                MinOrderAmount = 0,
                DeliveryFeeType = DeliveryFeeType.Fixed,
                DeliveryFeeValue = 0,
                SupportPhone = "",
                SupportWhatsApp = "",
                IsAcceptingOrders = false,
                RoutingProfile = "driving"
            });
        }

        await db.SaveChangesAsync();
    }
}
