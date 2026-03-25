using System.ComponentModel.DataAnnotations;

namespace AdminDashboard.Entities;

public class DriverLocation
{
    public int Id { get; set; }
    public int DriverId { get; set; }
    public Driver? Driver { get; set; }

    public double Lat { get; set; }
    public double Lng { get; set; }
    public double SpeedMps { get; set; }
    public double HeadingDeg { get; set; }
    // Horizontal accuracy in meters (from GPS when available)
    public double AccuracyMeters { get; set; }
    public DateTime UpdatedAtUtc { get; set; } = DateTime.UtcNow;

    // Optional: last N points not stored here; admin builds polyline from an in-memory ring buffer
}

public class Rating
{
    public int Id { get; set; }
    public int OrderId { get; set; }
    public int DriverId { get; set; }
    public int CustomerId { get; set; }

    // Driver rating (1-5). If the customer rates the restaurant first, we may create a row with Stars=0
    // then later fill driver Stars. لذلك ممنوع الاعتماد على أنها دائماً 1-5.
    public int Stars { get; set; }
    [MaxLength(800)]
    public string? Comment { get; set; }

    // Restaurant rating (1-5)
    public int? RestaurantStars { get; set; }
    [MaxLength(800)]
    public string? RestaurantComment { get; set; }
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}


public class OrderRating
{
    // One rating per order (PK = OrderId) to enforce uniqueness.
    [Key]
    public int OrderId { get; set; }

    // Restaurant rating (1-5)
    public int RestaurantRate { get; set; }

    // Driver rating (1-5). If no driver assigned, client still sends 5 but backend will store it.
    public int DriverRate { get; set; }

    [MaxLength(800)]
    public string? Comment { get; set; }

    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}

public class ComplaintThread
{
    public int Id { get; set; }
    public int CustomerId { get; set; }
    public int? OrderId { get; set; }

    [MaxLength(200)]
    public string Title { get; set; } = "";

    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;

    // Unread tracking
    public DateTime? LastAdminSeenAtUtc { get; set; }
    public DateTime? LastCustomerSeenAtUtc { get; set; }

    public DateTime UpdatedAtUtc { get; set; } = DateTime.UtcNow;
    public List<ComplaintMessage> Messages { get; set; } = new();
}

public class ComplaintMessage
{
    public int Id { get; set; }
    public int ThreadId { get; set; }
    public ComplaintThread? Thread { get; set; }

    public bool FromAdmin { get; set; }

    [MaxLength(2000)]
    public string Message { get; set; } = "";

    // Optional idempotency key for clients (e.g. Firebase message id / local uuid).
    // NOTE: Some code paths may use a constructor that requires this key, so we keep it
    // on the entity and provide safe overloads.
    [MaxLength(120)]
    public string FirebaseKey { get; set; } = Guid.NewGuid().ToString("N");

    public ComplaintMessage() { }

    public ComplaintMessage(int threadId, bool fromAdmin, string message)
    {
        ThreadId = threadId;
        FromAdmin = fromAdmin;
        Message = message;
        FirebaseKey = Guid.NewGuid().ToString("N");
    }

    public ComplaintMessage(int threadId, bool fromAdmin, string message, string firebaseKey)
    {
        ThreadId = threadId;
        FromAdmin = fromAdmin;
        Message = message;
        FirebaseKey = string.IsNullOrWhiteSpace(firebaseKey) ? Guid.NewGuid().ToString("N") : firebaseKey;
    }

    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}
