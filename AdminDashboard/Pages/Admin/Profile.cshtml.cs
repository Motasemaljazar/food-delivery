using AdminDashboard.Data;
using AdminDashboard.Security;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;

namespace AdminDashboard.Pages.Admin;

public class ProfileModel : PageModel
{
    private readonly AppDbContext _db;
    public ProfileModel(AppDbContext db) => _db = db;

    [BindProperty] public string Email { get; set; } = "admin";
    [BindProperty] public string? NewPassword { get; set; }
    public string? Status { get; set; }

    public async Task OnGet()
    {
        var user = await _db.AdminUsers.AsNoTracking().FirstAsync();
        Email = user.Email;
    }

    public async Task<IActionResult> OnPost()
    {
        var user = await _db.AdminUsers.FirstAsync();
        user.Email = Email.Trim();
        if (!string.IsNullOrWhiteSpace(NewPassword))
        {
            var (hash, salt) = AdminPassword.HashPassword(NewPassword);
            user.PasswordHash = hash;
            user.PasswordSalt = salt;
        }
        user.UpdatedAtUtc = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        Status = "تم الحفظ";
        return Page();
    }
}
