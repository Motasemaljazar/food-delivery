using AdminDashboard.Entities;
using AdminDashboard.Data;
using FirebaseAdmin;
using FirebaseAdmin.Messaging;
using Google.Apis.Auth.OAuth2;
using Microsoft.EntityFrameworkCore;

namespace AdminDashboard.Services;

/// <summary>
/// FCM sender using Firebase Admin SDK.
/// Reads service account JSON from:
/// 1) env FIREBASE_SERVICE_ACCOUNT_PATH
/// 2) ContentRoot/firebase-service-account.json
/// </summary>
public class FcmService
{
    private readonly AppDbContext _db;
    private readonly ILogger<FcmService> _logger;
    private bool _initialized;

    public FcmService(AppDbContext db, ILogger<FcmService> logger)
    {
        _db = db;
        _logger = logger;
    }

    private void EnsureInitialized()
    {
        if (_initialized) return;
        try
        {
            var path = Environment.GetEnvironmentVariable("FIREBASE_SERVICE_ACCOUNT_PATH");
            if (string.IsNullOrWhiteSpace(path))
                path = Path.Combine(AppContext.BaseDirectory, "firebase-service-account.json");

            if (!File.Exists(path))
            {
                _logger.LogWarning("FCM disabled: service account file not found at {Path}", path);
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
            _logger.LogInformation("FCM initialized using {Path}", path);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "FCM init failed");
        }
        finally
        {
            _initialized = true;
        }
    }

    public async Task RegisterTokenAsync(DeviceUserType userType, int userId, string fcmToken, string? platform)
    {
        if (string.IsNullOrWhiteSpace(fcmToken)) return;
        fcmToken = fcmToken.Trim();
        var now = DateTime.UtcNow;

        var existing = await _db.DeviceTokens.FirstOrDefaultAsync(x => x.FcmToken == fcmToken);
        if (existing == null)
        {
            _db.DeviceTokens.Add(new DeviceToken
            {
                UserType = userType,
                UserId = userId,
                FcmToken = fcmToken,
                Platform = platform,
                CreatedAtUtc = now,
                LastSeenAtUtc = now
            });
        }
        else
        {
            existing.UserType = userType;
            existing.UserId = userId;
            existing.Platform = platform;
            existing.LastSeenAtUtc = now;
        }
        await _db.SaveChangesAsync();
    }

    public async Task UnregisterTokenAsync(string fcmToken)
    {
        if (string.IsNullOrWhiteSpace(fcmToken)) return;
        fcmToken = fcmToken.Trim();
        var existing = await _db.DeviceTokens.FirstOrDefaultAsync(x => x.FcmToken == fcmToken);
        if (existing != null)
        {
            _db.DeviceTokens.Remove(existing);
            await _db.SaveChangesAsync();
        }
    }

    public async Task SendToUserAsync(DeviceUserType userType, int userId, string title, string body, Dictionary<string, string>? data = null)
    {
        EnsureInitialized();
        if (FirebaseApp.DefaultInstance == null) return;

        var tokens = await _db.DeviceTokens.AsNoTracking()
            .Where(t => t.UserType == userType && t.UserId == userId)
            .Select(t => t.FcmToken)
            .Distinct()
            .ToListAsync();
        if (tokens.Count == 0) return;

        var msg = new MulticastMessage
        {
            Tokens = tokens,
            Notification = new FirebaseAdmin.Messaging.Notification { Title = title, Body = body },
            Data = data ?? new Dictionary<string, string>()
        };

        try
        {
            var res = await FirebaseMessaging.DefaultInstance.SendEachForMulticastAsync(msg);
            _logger.LogInformation("FCM sent to user {UserType}#{UserId}: {Success}/{Total}", userType, userId, res.SuccessCount, tokens.Count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "FCM send failed");
        }
    }

    public async Task SendToTopicAsync(string topic, string title, string body, Dictionary<string, string>? data = null)
    {
        EnsureInitialized();
        if (FirebaseApp.DefaultInstance == null) return;

        try
        {
            var msg = new Message
            {
                Topic = topic,
                Notification = new FirebaseAdmin.Messaging.Notification { Title = title, Body = body },
                Data = data ?? new Dictionary<string, string>()
            };
            await FirebaseMessaging.DefaultInstance.SendAsync(msg);
            _logger.LogInformation("FCM sent to topic {Topic}", topic);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "FCM topic send failed");
        }
    }
}
