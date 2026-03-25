using Microsoft.AspNetCore.SignalR;

namespace AdminDashboard.Hubs;

// Hub for realtime driver tracking
public class TrackingHub : Hub
{
    // Admin dashboard: joins group "admin"
    public Task JoinAdmin() => Groups.AddToGroupAsync(Context.ConnectionId, "admin");

    // Customer app may join a specific order/customer group (optional)
    public Task JoinCustomer(int customerId) => Groups.AddToGroupAsync(Context.ConnectionId, $"customer-{customerId}");

    // Driver app joins its driver group (optional)
    public Task JoinDriver(int driverId) => Groups.AddToGroupAsync(Context.ConnectionId, $"driver-{driverId}");
}
