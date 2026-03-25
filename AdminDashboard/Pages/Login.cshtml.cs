using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace AdminDashboard.Pages;

/// <summary>
/// Backwards-compatible redirect for old /Login route.
/// The real admin login page is /Admin/Login.
/// </summary>
public class LoginModel : PageModel
{
    public IActionResult OnGet()
        => Redirect("/Admin/Login");

    public IActionResult OnPost()
        => Redirect("/Admin/Login");
}
