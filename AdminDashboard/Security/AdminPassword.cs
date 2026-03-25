using System.Security.Cryptography;
using System.Text;

namespace AdminDashboard.Security;

public static class AdminPassword
{
    public static (string hash, string salt) HashPassword(string password)
    {
        var saltBytes = RandomNumberGenerator.GetBytes(16);
        using var pbkdf2 = new Rfc2898DeriveBytes(password, saltBytes, 100000, HashAlgorithmName.SHA256);
        var hashBytes = pbkdf2.GetBytes(32);
        return (Convert.ToBase64String(hashBytes), Convert.ToBase64String(saltBytes));
    }

    public static bool Verify(string password, string hashB64, string saltB64)
    {
        if (string.IsNullOrWhiteSpace(hashB64) || string.IsNullOrWhiteSpace(saltB64)) return false;
        var saltBytes = Convert.FromBase64String(saltB64);
        using var pbkdf2 = new Rfc2898DeriveBytes(password, saltBytes, 100000, HashAlgorithmName.SHA256);
        var hashBytes = pbkdf2.GetBytes(32);
        var expected = Convert.FromBase64String(hashB64);
        return CryptographicOperations.FixedTimeEquals(hashBytes, expected);
    }
}
