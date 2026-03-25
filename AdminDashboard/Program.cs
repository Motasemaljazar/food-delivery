using AdminDashboard.Data;
using AdminDashboard.Hubs;
using AdminDashboard.Security;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;
using System.Text.Json.Serialization;

var builder = WebApplication.CreateBuilder(args);

// Ensure WebRoot is consistently "wwwroot" across hosting environments
builder.WebHost.UseWebRoot("wwwroot");

// If the app is behind a reverse proxy (Nginx/IIS/Cloud), we must trust forwarded headers
// so HTTPS redirects, absolute URLs, and client IPs behave correctly.
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    // Include X-Forwarded-Host so Request.Host reflects the public host behind a reverse proxy.
    // This is critical for generating correct absolute URLs for images/logos/banners in the apps.
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto | ForwardedHeaders.XForwardedHost;
    // NOTE: In many managed hosts, you can't reliably enumerate proxy IPs.
    // Clearing KnownNetworks/Proxies lets ASP.NET Core accept forwarded headers.
    options.KnownNetworks.Clear();
    options.KnownProxies.Clear();
});

builder.Services
    .AddRazorPages(opts =>
    {
        // Protect all admin pages (Pages/Admin/*)
        opts.Conventions.AuthorizeFolder("/Admin", "AdminOnly");
        // Allow admin login page
        opts.Conventions.AllowAnonymousToPage("/Admin/Login");
    });
builder.Services
    .AddControllers()
    .AddJsonOptions(o =>
    {
        // Prevent `System.Text.Json` cycle errors when returning EF entities.
        o.JsonSerializerOptions.ReferenceHandler = ReferenceHandler.IgnoreCycles;
        o.JsonSerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull;
        // Frontends (Flutter Web + Admin JS) expect camelCase JSON.
        o.JsonSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
        o.JsonSerializerOptions.DictionaryKeyPolicy = JsonNamingPolicy.CamelCase;
    });
builder.Services.AddSignalR();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddCors();

builder.Services.Configure<AppSecurityOptions>(builder.Configuration.GetSection("Security"));

builder.Services.AddScoped<NotificationService>();
builder.Services.AddScoped<AdminDashboard.Services.FcmService>();
builder.Services.AddScoped<AdminDashboard.Services.FirebaseAdminService>();

// Admin cookie authentication
builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(opts =>
    {
        opts.LoginPath = "/Admin/Login";
        opts.LogoutPath = "/Logout";
        opts.AccessDeniedPath = "/Admin/Login";
        opts.Cookie.Name = "restaurant_admin";
        opts.SlidingExpiration = true;
        // Session timeout
        opts.ExpireTimeSpan = TimeSpan.FromHours(12);
    });

builder.Services.AddHttpContextAccessor();
builder.Services.AddSingleton<Microsoft.AspNetCore.Authorization.IAuthorizationHandler, AdminDashboard.Security.AdminApiKeyAuthorizationHandler>();
builder.Services.AddAuthorization(opts =>
{
    opts.AddPolicy("AdminOnly", policy =>
    {
        policy.Requirements.Add(new AdminDashboard.Security.AdminOnlyRequirement());
    });
});

var recreate = builder.Configuration.GetValue<bool>("Database:RecreateOnStart");

builder.Services.AddDbContext<AppDbContext>(opt =>
{
    var cs = builder.Configuration.GetConnectionString("DefaultConnection");
    opt.UseMySql(cs, ServerVersion.AutoDetect(cs));
});

var app = builder.Build();

// Fail fast in Production if critical secrets were not set.
if (app.Environment.IsProduction())
{
    var sec = app.Configuration.GetSection("Security").Get<AppSecurityOptions>() ?? new AppSecurityOptions();
    if (string.Equals(sec.AdminApiKey, "CHANGE_ME", StringComparison.OrdinalIgnoreCase)
        || string.Equals(sec.DriverTokenSecret, "DEV_SECRET_CHANGE_ME", StringComparison.OrdinalIgnoreCase))
    {
        throw new InvalidOperationException(
            "Production misconfiguration: please set Security:AdminApiKey and Security:DriverTokenSecret to secure values in appsettings.Production.json or environment variables.");
    }
}

// Database: apply EF Core migrations (creates/updates schema), then seed
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    if (recreate)
    {
        await db.Database.EnsureDeletedAsync();
    }
    await db.Database.MigrateAsync();
    await SchemaUpgrader.EnsureAsync(db);
    await DbSeeder.SeedAsync(db, app.Environment.IsDevelopment(), app.Configuration);
}


if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseForwardedHeaders();

if (app.Environment.IsProduction())
{
    app.UseHsts();
    app.UseHttpsRedirection();
}

// Add CORS-like headers for static uploads so Flutter Web can draw images on Canvas without being blocked.
// NOTE: Static files are served before endpoint routing, so the normal CORS middleware does NOT run for them.
app.Use(async (ctx, next) =>
{
    // Always allow cross-origin for uploaded assets (logos, banners, menu images, offers)
    // This is safe because these are public assets and required for the mobile/web apps.
    if (ctx.Request.Path.StartsWithSegments("/uploads", StringComparison.OrdinalIgnoreCase) ||
        ctx.Request.Path.StartsWithSegments("/assets", StringComparison.OrdinalIgnoreCase) ||
        ctx.Request.Path.StartsWithSegments("/images", StringComparison.OrdinalIgnoreCase))
    {
        ctx.Response.Headers["Access-Control-Allow-Origin"] = "*";
        ctx.Response.Headers["Cross-Origin-Resource-Policy"] = "cross-origin";
    }

    await next();
});

// Serve static files with a broader set of image mime-types (webp/heic/avif/svg/jfif) used by phones/browsers.
var contentTypeProvider = new Microsoft.AspNetCore.StaticFiles.FileExtensionContentTypeProvider();
contentTypeProvider.Mappings[".webp"] = "image/webp";
contentTypeProvider.Mappings[".avif"] = "image/avif";
contentTypeProvider.Mappings[".heic"] = "image/heic";
contentTypeProvider.Mappings[".heif"] = "image/heif";
contentTypeProvider.Mappings[".svg"]  = "image/svg+xml";
contentTypeProvider.Mappings[".jfif"] = "image/jpeg";

app.UseStaticFiles(new StaticFileOptions
{
    ContentTypeProvider = contentTypeProvider,
    // If an unknown extension is uploaded, still serve it (with octet-stream) so the URL doesn't 404.
    ServeUnknownFileTypes = true
});

// IMPORTANT: For endpoint routing, CORS must run AFTER UseRouting and BEFORE auth/endpoint mapping.
app.UseRouting();

// CORS:
// - Development: allow all (for Flutter Web local testing)
// - Production: allow only explicit origins (for security)
if (app.Environment.IsDevelopment())
{
    app.UseCors(policy =>
    {
        policy
            .AllowAnyHeader()
            .AllowAnyMethod()
            .AllowCredentials()
            .SetIsOriginAllowed(_ => true);
    });
}
else
{
    var allowed = app.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? Array.Empty<string>();
    if (allowed.Length > 0)
    {
        app.UseCors(policy =>
        {
            policy
                .WithOrigins(allowed)
                .AllowAnyHeader()
                .AllowAnyMethod()
                .AllowCredentials();
        });
    }
}

app.UseAuthentication();
app.UseAuthorization();

// Simple health endpoint for monitoring (and to quickly verify the server is up).
app.MapGet("/health", () => Results.Json(new { status = "ok", utc = DateTime.UtcNow }))
   .AllowAnonymous();

app.MapControllers();
app.MapRazorPages();
app.MapHub<TrackingHub>("/hubs/tracking");
app.MapHub<NotifyHub>("/hubs/notify");

app.Run();
