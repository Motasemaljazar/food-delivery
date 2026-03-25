using AdminDashboard.Data;
using AdminDashboard.Security;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;

namespace AdminDashboard.Pages.Admin;

public class LoginModel : PageModel
{
    private readonly AppDbContext _db;
    public LoginModel(AppDbContext db) => _db = db;

    [BindProperty] public string Email { get; set; } = "admin";
    [BindProperty] public string Password { get; set; } = "admin123";

    public string? Error { get; set; }

    // Branding (from Admin Settings)
    public string RestaurantName { get; private set; } = "لوحة التحكم";
    public string? LogoUrl { get; private set; }

    private async Task LoadBrandingAsync()
    {
        var s = await _db.RestaurantSettings.AsNoTracking().FirstOrDefaultAsync();
        if (s != null)
        {
            RestaurantName = string.IsNullOrWhiteSpace(s.RestaurantName) ? "لوحة التحكم" : s.RestaurantName;
            LogoUrl = string.IsNullOrWhiteSpace(s.LogoUrl) ? null : s.LogoUrl;
        }
    }

    public async Task<IActionResult> OnGet()
    {
        if (User?.Identity?.IsAuthenticated == true)
            return Redirect("/Admin/Orders");
        await LoadBrandingAsync();
        return Page();
    }

    public async Task<IActionResult> OnPost()
    {
        await LoadBrandingAsync();
        var user = await _db.AdminUsers.AsNoTracking().FirstOrDefaultAsync(x => x.Email == Email);
        if (user == null || !AdminPassword.Verify(Password, user.PasswordHash, user.PasswordSalt))
        {
            Error = "بيانات الدخول غير صحيحة";
            return Page();
        }

        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new(ClaimTypes.Name, user.Email),
            new("role", "admin")
        };
        var identity = new ClaimsIdentity(claims, CookieAuthenticationDefaults.AuthenticationScheme);
        await HttpContext.SignInAsync(CookieAuthenticationDefaults.AuthenticationScheme, new ClaimsPrincipal(identity));
        return Redirect("/Admin/Orders");
    }
}
