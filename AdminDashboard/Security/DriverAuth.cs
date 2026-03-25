using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;

namespace AdminDashboard.Security;

public static class DriverAuth
{
    // token format: driverId:expUnix:signatureBase64Url
    public static string IssueToken(int driverId, IOptions<AppSecurityOptions> opts)
    {
        var exp = DateTimeOffset.UtcNow.AddMinutes(opts.Value.DriverTokenMinutes).ToUnixTimeSeconds();
        var payload = $"{driverId}:{exp}";
        var sig = Sign(payload, opts.Value.DriverTokenSecret);
        return $"{payload}:{sig}";
    }

    public static bool TryValidate(string token, IOptions<AppSecurityOptions> opts, out int driverId)
    {
        driverId = 0;
        var parts = token.Split(':');
        if (parts.Length != 3) return false;
        if (!int.TryParse(parts[0], out driverId)) return false;
        if (!long.TryParse(parts[1], out var expUnix)) return false;
        if (DateTimeOffset.UtcNow.ToUnixTimeSeconds() > expUnix) return false;

        var payload = $"{parts[0]}:{parts[1]}";
        var expected = Sign(payload, opts.Value.DriverTokenSecret);
        return ConstantTimeEquals(expected, parts[2]);
    }

    private static string Sign(string payload, string secret)
    {
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(secret));
        var bytes = hmac.ComputeHash(Encoding.UTF8.GetBytes(payload));
        return Base64Url(bytes);
    }

    private static string Base64Url(byte[] bytes)
        => Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private static bool ConstantTimeEquals(string a, string b)
    {
        if (a.Length != b.Length) return false;
        var diff = 0;
        for (var i = 0; i < a.Length; i++) diff |= a[i] ^ b[i];
        return diff == 0;
    }
}
