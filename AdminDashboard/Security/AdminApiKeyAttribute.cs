using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.Options;

namespace AdminDashboard.Security;

[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method)]
public class AdminApiKeyAttribute : Attribute, IAsyncActionFilter
{
    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var opts = context.HttpContext.RequestServices.GetRequiredService<IOptions<AppSecurityOptions>>().Value;
        if (!context.HttpContext.Request.Headers.TryGetValue("X-ADMIN-KEY", out var key) || key != opts.AdminApiKey)
        {
            context.Result = new UnauthorizedObjectResult(new { error = "Missing or invalid X-ADMIN-KEY" });
            return;
        }

        await next();
    }
}
