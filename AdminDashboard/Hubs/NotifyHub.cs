using AdminDashboard.Security;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Options;

namespace AdminDashboard.Hubs;

public class NotifyHub : Hub
{
    private readonly IOptions<AppSecurityOptions> _opts;
    public NotifyHub(IOptions<AppSecurityOptions> opts) => _opts = opts;

    public override async Task OnConnectedAsync()
    {
        // Admin dashboard connects with Cookie Auth; if authenticated, auto-join admin group.
        if (Context.User?.Identity?.IsAuthenticated == true)
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, "admin");
        }
        await base.OnConnectedAsync();
    }

    public Task JoinCustomer(int customerId)
        => Groups.AddToGroupAsync(Context.ConnectionId, $"customer-{customerId}");

    public Task JoinDriver(string token)
    {
        if (!DriverAuth.TryValidate(token, _opts, out var driverId))
            throw new HubException("Invalid driver token");
        return Groups.AddToGroupAsync(Context.ConnectionId, $"driver-{driverId}");
    }
}
