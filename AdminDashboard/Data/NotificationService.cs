using AdminDashboard.Entities;
using AdminDashboard.Hubs;
using AdminDashboard.Services;
using Microsoft.AspNetCore.SignalR;

namespace AdminDashboard.Data;

public class NotificationService
{
    private readonly AppDbContext _db;
    private readonly IHubContext<NotifyHub> _hub;
    private readonly FcmService _fcm;

    public NotificationService(AppDbContext db, IHubContext<NotifyHub> hub, FcmService fcm)
    {
        _db = db;
        _hub = hub;
        _fcm = fcm;
    }

    public async Task CreateAndBroadcastAsync(NotificationUserType userType, int? userId, string title, string body, int? relatedOrderId = null)
    {
        var n = new Notification
        {
            UserType = userType,
            UserId = userId,
            Title = title,
            Body = body,
            RelatedOrderId = relatedOrderId,
            IsRead = false,
            CreatedAtUtc = DateTime.UtcNow
        };
        _db.Notifications.Add(n);
        await _db.SaveChangesAsync();

        var payload = new { n.Id, userType = n.UserType, n.UserId, n.Title, n.Body, n.RelatedOrderId, n.IsRead, n.CreatedAtUtc };

        // Broadcast
        if (userType == NotificationUserType.Admin)
        {
            await _hub.Clients.Group("admin").SendAsync("notification", payload);
            // Push to admins topic (FCM) - keep backward compatibility (admins) + required (admin)
            await _fcm.SendToTopicAsync("admin", title, body,
                relatedOrderId != null ? new Dictionary<string, string> { ["orderId"] = relatedOrderId.Value.ToString() } : null);
            await _fcm.SendToTopicAsync("admins", title, body,
                relatedOrderId != null ? new Dictionary<string, string> { ["orderId"] = relatedOrderId.Value.ToString() } : null);
        }
        else if (userType == NotificationUserType.Customer && userId != null)
        {
            await _hub.Clients.Group($"customer-{userId}").SendAsync("notification", payload);
            // ⚠️ لا نرسل Push للزبون من هنا (لمنع أي إشعارات خارج المطلوب).
        }
        else if (userType == NotificationUserType.Driver && userId != null)
        {
            await _hub.Clients.Group($"driver-{userId}").SendAsync("notification", payload);
            // ⚠️ لا نرسل Push للسائق من هنا (الإشعارات المسموحة للسائق يتم إرسالها فقط عند تعيين طلب).
        }
    }

    public async Task SendCustomerOrderStatusPushIfNeededAsync(
        int customerId,
        int orderId,
        OrderStatus status,
        int? prepEtaMinutes = null,
        int? deliveryEtaMinutes = null)
    {
        // الزبون: حسب المتطلبات الحالية (الدفعة 1)
        string title = "حالة الطلب";
        string? body = null;

        if (status == OrderStatus.New)
        {
            title = "تم استلام طلبك";
            body = $"تم إنشاء طلبك رقم #{orderId} بنجاح";
        }
        else if (status == OrderStatus.Confirmed)
        {
            var prep = prepEtaMinutes ?? 0;
            var del = deliveryEtaMinutes ?? 0;
            if (prep > 0 || del > 0)
                body = $"تم تأكيد الطلب ✅ (تحضير: {prep} د، توصيل: {del} د)";
            else
                body = "تم تأكيد الطلب ✅";
        }
        else if (status == OrderStatus.Preparing)
        {
            body = "جاري تحضير طلبك 👨‍🍳";
        }
        else if (status == OrderStatus.ReadyForPickup)
        {
            body = "طلبك جاهز ✅";
        }
        else if (status == OrderStatus.WithDriver)
        {
            body = "طلبك في الطريق 🚚";
        }
        else if (status == OrderStatus.Delivered)
        {
            body = "تم تسليم طلبك ✅ شكراً لانتظاركم";
        }
        else if (status == OrderStatus.Cancelled)
        {
            body = "تم إلغاء طلبك";
        }

        if (string.IsNullOrWhiteSpace(body)) return;

        await _fcm.SendToUserAsync(DeviceUserType.Customer, customerId,
            title,
            body,
            new Dictionary<string, string> { ["orderId"] = orderId.ToString(), ["status"] = status.ToString() });
    }

    // When admin sets/updates ETA (prep + delivery), we must notify the customer
    // even if the status didn't change.
    public async Task SendCustomerEtaUpdatedPushAsync(int customerId, int orderId, int? prepEtaMinutes, int? deliveryEtaMinutes)
    {
        var prep = prepEtaMinutes ?? 0;
        var del = deliveryEtaMinutes ?? 0;
        if (prep <= 0 && del <= 0) return;

        var title = "تحديث الوقت المتوقع";
        var body = $"تم تحديد الوقت المتوقع ✅ (تحضير: {prep} د، توصيل: {del} د)";

        await _fcm.SendToUserAsync(DeviceUserType.Customer, customerId, title, body,
            new Dictionary<string, string> { ["orderId"] = orderId.ToString(), ["type"] = "eta" });
    }


    public async Task SendAdminChatPushAsync(int? relatedOrderId, int customerId, string? message)
    {
        var snippet = (message ?? "").Trim();
        if (snippet.Length > 80) snippet = snippet.Substring(0, 80) + "…";
        var title = "رسالة جديدة";
        var body = relatedOrderId != null
            ? $"طلب #{relatedOrderId}: {snippet}"
            : $"من الزبون #{customerId}: {snippet}";

        var data = relatedOrderId != null
            ? new Dictionary<string, string> { ["orderId"] = relatedOrderId.Value.ToString(), ["type"] = "chat" }
            : new Dictionary<string, string> { ["customerId"] = customerId.ToString(), ["type"] = "chat" };

        await _fcm.SendToTopicAsync("admin", title, body, data);
        await _fcm.SendToTopicAsync("admins", title, body, data);
    }

    public async Task SendCustomerChatPushAsync(int customerId, int? relatedOrderId, string? message)
    {
        var snippet = (message ?? "").Trim();
        if (snippet.Length > 80) snippet = snippet.Substring(0, 80) + "…";
        var title = "رسالة جديدة";
        var body = relatedOrderId != null
            ? $"رد بخصوص طلبك #{relatedOrderId}: {snippet}"
            : $"رد جديد: {snippet}";

        var data = new Dictionary<string, string> { ["type"] = "chat" };
        if (relatedOrderId != null) data["orderId"] = relatedOrderId.Value.ToString();

        await _fcm.SendToUserAsync(DeviceUserType.Customer, customerId, title, body, data);
    }

}