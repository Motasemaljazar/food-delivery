using FirebaseAdmin;
using FirebaseAdmin.Auth;
using Google.Apis.Auth.OAuth2;
using Microsoft.AspNetCore.Hosting;

namespace AdminDashboard.Services;

/// <summary>
/// Firebase Admin helpers for:
/// - verifying Firebase Auth ID tokens (Email/Google)
/// Uses the same service account file as FCM.
/// </summary>
public class FirebaseAdminService
{
    private readonly ILogger<FirebaseAdminService> _logger;
    private readonly IWebHostEnvironment _env;
    private bool _initialized;

    public FirebaseAdminService(ILogger<FirebaseAdminService> logger, IWebHostEnvironment env)
    {
        _logger = logger;
        _env = env;
    }

    private void EnsureInitialized()
    {
        if (_initialized) return;
        try
        {
            var path = Environment.GetEnvironmentVariable("FIREBASE_SERVICE_ACCOUNT_PATH");
            if (string.IsNullOrWhiteSpace(path))
            {
                // Prefer project/content root (works in Visual Studio / dotnet run)
                // then fall back to output folder (works if file is copied to bin).
                var inContentRoot = Path.Combine(_env.ContentRootPath, "firebase-service-account.json");
                path = File.Exists(inContentRoot)
                    ? inContentRoot
                    : Path.Combine(AppContext.BaseDirectory, "firebase-service-account.json");
            }

            if (!File.Exists(path))
            {
                _logger.LogWarning("Firebase Admin disabled: service account file not found at {Path}", path);
                _initialized = true;
                return;
            }

            if (FirebaseApp.DefaultInstance == null)
            {
                FirebaseApp.Create(new AppOptions
                {
                    Credential = GoogleCredential.FromFile(path)
                });
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Firebase Admin init failed");
        }
        finally
        {
            _initialized = true;
        }
    }

    public async Task<FirebaseToken?> VerifyIdTokenAsync(string idToken)
    {
        EnsureInitialized();
        if (FirebaseApp.DefaultInstance == null) return null;

        try
        {
            return await FirebaseAuth.DefaultInstance.VerifyIdTokenAsync(idToken);
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// حذف مستخدم من Firebase Authentication بالـ UID (مثلاً عند حذف حساب الزبون من لوحة التحكم).
    /// </summary>
    public async Task<bool> DeleteUserAsync(string uid)
    {
        if (string.IsNullOrWhiteSpace(uid)) return false;
        EnsureInitialized();
        if (FirebaseApp.DefaultInstance == null) return false;

        try
        {
            await FirebaseAuth.DefaultInstance.DeleteUserAsync(uid.Trim());
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Firebase DeleteUser failed for UID {Uid}", uid);
            return false;
        }
    }
}
