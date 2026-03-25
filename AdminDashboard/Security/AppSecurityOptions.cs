namespace AdminDashboard.Security;

public class AppSecurityOptions
{
    public string AdminApiKey { get; set; } = "CHANGE_ME";
    public string DriverTokenSecret { get; set; } = "DEV_SECRET_CHANGE_ME";
    public int DriverTokenMinutes { get; set; } = 60 * 24;
}
