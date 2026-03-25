using System;
using Microsoft.EntityFrameworkCore;

namespace AdminDashboard.Data;

/// <summary>
/// Lightweight SQLite schema upgrader.
/// IMPORTANT: project uses EnsureCreated(), which does not apply schema updates on existing DB files.
/// This upgrader makes sure newer tables/columns exist so older DBs keep working.
/// </summary>
public static class SchemaUpgrader
{
    public static async Task EnsureAsync(AppDbContext db)
    {
        // This upgrader is **SQLite-only**.
        // When the project runs on MySQL/MariaDB, EF Core creates the schema via
        // EnsureCreated()/Migrations, and the SQLite-specific SQL below (sqlite_master,
        // PRAGMA, AUTOINCREMENT, etc.) will fail.
        if (!string.Equals(db.Database.ProviderName, "Microsoft.EntityFrameworkCore.Sqlite", StringComparison.OrdinalIgnoreCase))
            return;

        // Tables
        // Discounts system (market-style).
        await ExecAsync(db, "DROP TABLE IF EXISTS Coupons;");
        await ExecAsync(db, "DROP INDEX IF EXISTS IX_Coupons_Code;");

        await EnsureTableAsync(db, "ProductImages",
            "CREATE TABLE IF NOT EXISTS ProductImages (Id INTEGER PRIMARY KEY AUTOINCREMENT, ProductId INTEGER NOT NULL, Url TEXT NOT NULL, SortOrder INTEGER NOT NULL DEFAULT 0, IsPrimary INTEGER NOT NULL DEFAULT 0)");

        await EnsureTableAsync(db, "ProductVariants",
            "CREATE TABLE IF NOT EXISTS ProductVariants (Id INTEGER PRIMARY KEY AUTOINCREMENT, ProductId INTEGER NOT NULL, Name TEXT NOT NULL, PriceDelta TEXT NOT NULL DEFAULT 0, IsActive INTEGER NOT NULL DEFAULT 1, SortOrder INTEGER NOT NULL DEFAULT 0)");

        await EnsureTableAsync(db, "ProductAddons",
            "CREATE TABLE IF NOT EXISTS ProductAddons (Id INTEGER PRIMARY KEY AUTOINCREMENT, ProductId INTEGER NOT NULL, Name TEXT NOT NULL, Price TEXT NOT NULL DEFAULT 0, IsActive INTEGER NOT NULL DEFAULT 1, SortOrder INTEGER NOT NULL DEFAULT 0)");

        await EnsureTableAsync(db, "Offers",
            "CREATE TABLE IF NOT EXISTS Offers (Id INTEGER PRIMARY KEY AUTOINCREMENT, Title TEXT NOT NULL, Description TEXT NULL, ImageUrl TEXT NULL, PriceBefore TEXT NULL, PriceAfter TEXT NULL, Code TEXT NULL, StartsAtUtc TEXT NULL, EndsAtUtc TEXT NULL, IsActive INTEGER NOT NULL DEFAULT 1)");

        // FCM Device Tokens
        await EnsureTableAsync(db, "DeviceTokens",
            "CREATE TABLE IF NOT EXISTS DeviceTokens (Id INTEGER PRIMARY KEY AUTOINCREMENT, UserType INTEGER NOT NULL DEFAULT 0, UserId INTEGER NOT NULL, FcmToken TEXT NOT NULL, Platform TEXT NULL, CreatedAtUtc TEXT NOT NULL, LastSeenAtUtc TEXT NOT NULL)");

        // Ratings (customer -> driver) after delivered
        await EnsureTableAsync(db, "Ratings",
            "CREATE TABLE IF NOT EXISTS Ratings (Id INTEGER PRIMARY KEY AUTOINCREMENT, OrderId INTEGER NOT NULL, DriverId INTEGER NOT NULL, CustomerId INTEGER NOT NULL, Stars INTEGER NOT NULL, Comment TEXT NULL, CreatedAtUtc TEXT NOT NULL)");

        // Ratings: restaurant feedback (added later) - stored in same row to keep things simple.
        await EnsureColumnAsync(db, "Ratings", "RestaurantStars", "ALTER TABLE Ratings ADD COLUMN RestaurantStars INTEGER NULL");
        await EnsureColumnAsync(db, "Ratings", "RestaurantComment", "ALTER TABLE Ratings ADD COLUMN RestaurantComment TEXT NULL");

        // OrderRatings (mandatory combined rating after delivered)
        await EnsureTableAsync(db, "OrderRatings",
            "CREATE TABLE IF NOT EXISTS OrderRatings (OrderId INTEGER PRIMARY KEY, RestaurantRate INTEGER NOT NULL, DriverRate INTEGER NOT NULL, Comment TEXT NULL, CreatedAtUtc TEXT NOT NULL)");

        // Customer saved addresses
        await EnsureTableAsync(db, "CustomerAddresses",
            "CREATE TABLE IF NOT EXISTS CustomerAddresses (Id INTEGER PRIMARY KEY AUTOINCREMENT, CustomerId INTEGER NOT NULL, Title TEXT NOT NULL DEFAULT 'البيت', AddressText TEXT NOT NULL DEFAULT '', Latitude REAL NOT NULL DEFAULT 0, Longitude REAL NOT NULL DEFAULT 0, Building TEXT NULL, Floor TEXT NULL, Apartment TEXT NULL, Notes TEXT NULL, IsDefault INTEGER NOT NULL DEFAULT 0, CreatedAtUtc TEXT NOT NULL, UpdatedAtUtc TEXT NOT NULL)");
        await ExecAsync(db, "CREATE UNIQUE INDEX IF NOT EXISTS IX_OrderRatings_OrderId ON OrderRatings(OrderId);");


        // Offers: extra fields
        await EnsureColumnAsync(db, "Offers", "ImageUrl", "ALTER TABLE Offers ADD COLUMN ImageUrl TEXT NULL");
        await EnsureColumnAsync(db, "Offers", "PriceBefore", "ALTER TABLE Offers ADD COLUMN PriceBefore TEXT NULL");
        await EnsureColumnAsync(db, "Offers", "PriceAfter", "ALTER TABLE Offers ADD COLUMN PriceAfter TEXT NULL");
        await EnsureColumnAsync(db, "Offers", "Code", "ALTER TABLE Offers ADD COLUMN Code TEXT NULL");

        // OfferProducts (Offer -> Products)
        await EnsureTableAsync(db, "OfferProducts", @"CREATE TABLE OfferProducts (
            Id INTEGER PRIMARY KEY AUTOINCREMENT,
            OfferId INTEGER NOT NULL,
            ProductId INTEGER NOT NULL
        );");

        // OfferCategories (Offer -> Categories)
        await EnsureTableAsync(db, "OfferCategories", @"CREATE TABLE OfferCategories (
            Id INTEGER PRIMARY KEY AUTOINCREMENT,
            OfferId INTEGER NOT NULL,
            CategoryId INTEGER NOT NULL
        );");


await EnsureTableAsync(db, "Discounts",
    "CREATE TABLE IF NOT EXISTS Discounts (Id INTEGER PRIMARY KEY AUTOINCREMENT, Title TEXT NOT NULL DEFAULT 'خصم', TargetType INTEGER NOT NULL, TargetId INTEGER NULL, ValueType INTEGER NOT NULL, Percent REAL NULL, Amount REAL NULL, MinOrderAmount REAL NULL, IsActive INTEGER NOT NULL DEFAULT 1, StartsAtUtc TEXT NULL, EndsAtUtc TEXT NULL, BadgeText TEXT NULL);");
await ExecAsync(db, "CREATE INDEX IF NOT EXISTS IX_Discounts_Target ON Discounts(TargetType, TargetId);");
await ExecAsync(db, "CREATE INDEX IF NOT EXISTS IX_Discounts_Active ON Discounts(IsActive);");
        await ExecAsync(db, "CREATE UNIQUE INDEX IF NOT EXISTS IX_OfferProducts_Offer_Product ON OfferProducts(OfferId,ProductId);");
        await ExecAsync(db, "CREATE UNIQUE INDEX IF NOT EXISTS IX_OfferCategories_Offer_Category ON OfferCategories(OfferId,CategoryId);");

// Columns (Orders ETA fields)
        // ProductImages primary flag
        await EnsureColumnAsync(db, "ProductImages", "IsPrimary", "ALTER TABLE ProductImages ADD COLUMN IsPrimary INTEGER NOT NULL DEFAULT 0");

        await EnsureColumnAsync(db, "Orders", "DriverConfirmedAtUtc", "ALTER TABLE Orders ADD COLUMN DriverConfirmedAtUtc TEXT NULL");
        await EnsureColumnAsync(db, "Orders", "DeliveredAtUtc", "ALTER TABLE Orders ADD COLUMN DeliveredAtUtc TEXT NULL");
        await EnsureColumnAsync(db, "Orders", "OrderEditableUntilUtc", "ALTER TABLE Orders ADD COLUMN OrderEditableUntilUtc TEXT NULL");
        await EnsureColumnAsync(db, "Orders", "CustomerAddressId", "ALTER TABLE Orders ADD COLUMN CustomerAddressId INTEGER NULL");
        await EnsureColumnAsync(db, "Orders", "DeliveryDistanceKm", "ALTER TABLE Orders ADD COLUMN DeliveryDistanceKm REAL NOT NULL DEFAULT 0");
        await EnsureColumnAsync(db, "Orders", "DistanceKm", "ALTER TABLE Orders ADD COLUMN DistanceKm REAL NOT NULL DEFAULT 0");

        await EnsureColumnAsync(db, "Orders", "PrepEtaMinutes", "ALTER TABLE Orders ADD COLUMN PrepEtaMinutes INTEGER NULL");
        await EnsureColumnAsync(db, "Orders", "DeliveryEtaMinutes", "ALTER TABLE Orders ADD COLUMN DeliveryEtaMinutes INTEGER NULL");
        await EnsureColumnAsync(db, "Orders", "ExpectedDeliveryAtUtc", "ALTER TABLE Orders ADD COLUMN ExpectedDeliveryAtUtc TEXT NULL");
        await EnsureColumnAsync(db, "Orders", "LastEtaUpdatedAtUtc", "ALTER TABLE Orders ADD COLUMN LastEtaUpdatedAtUtc TEXT NULL");

        // Orders: idempotency + cancel reason
        await EnsureColumnAsync(db, "Orders", "IdempotencyKey", "ALTER TABLE Orders ADD COLUMN IdempotencyKey TEXT NULL");
        await EnsureColumnAsync(db, "Orders", "CancelReasonCode", "ALTER TABLE Orders ADD COLUMN CancelReasonCode TEXT NULL");

await EnsureColumnAsync(db, "Orders", "TotalBeforeDiscount", "REAL NOT NULL DEFAULT 0");
await EnsureColumnAsync(db, "Orders", "CartDiscount", "REAL NOT NULL DEFAULT 0");


        // RestaurantSettings lat/lng
        await EnsureColumnAsync(db, "RestaurantSettings", "RestaurantLat", "ALTER TABLE RestaurantSettings ADD COLUMN RestaurantLat REAL NOT NULL DEFAULT 0");
        await EnsureColumnAsync(db, "RestaurantSettings", "RestaurantLng", "ALTER TABLE RestaurantSettings ADD COLUMN RestaurantLng REAL NOT NULL DEFAULT 0");

        // RestaurantSettings operational flags (older DBs may not have these columns)
        await EnsureColumnAsync(db, "RestaurantSettings", "IsAcceptingOrders", "ALTER TABLE RestaurantSettings ADD COLUMN IsAcceptingOrders INTEGER NOT NULL DEFAULT 0");
        await EnsureColumnAsync(db, "RestaurantSettings", "IsManuallyClosed", "ALTER TABLE RestaurantSettings ADD COLUMN IsManuallyClosed INTEGER NOT NULL DEFAULT 0");
        await EnsureColumnAsync(db, "RestaurantSettings", "ClosedMessage", "ALTER TABLE RestaurantSettings ADD COLUMN ClosedMessage TEXT NOT NULL DEFAULT 'المطعم مغلق حالياً'");
        await EnsureColumnAsync(db, "RestaurantSettings", "ClosedScreenImageUrl", "ALTER TABLE RestaurantSettings ADD COLUMN ClosedScreenImageUrl TEXT NULL");

        // RestaurantSettings social links
        await EnsureColumnAsync(db, "RestaurantSettings", "FacebookUrl", "ALTER TABLE RestaurantSettings ADD COLUMN FacebookUrl TEXT NULL");
        await EnsureColumnAsync(db, "RestaurantSettings", "InstagramUrl", "ALTER TABLE RestaurantSettings ADD COLUMN InstagramUrl TEXT NULL");
        await EnsureColumnAsync(db, "RestaurantSettings", "TelegramUrl", "ALTER TABLE RestaurantSettings ADD COLUMN TelegramUrl TEXT NULL");

        // RestaurantSettings branding extras
        await EnsureColumnAsync(db, "RestaurantSettings", "OffersColorHex", "ALTER TABLE RestaurantSettings ADD COLUMN OffersColorHex TEXT NOT NULL DEFAULT '#E11D48'");
        await EnsureColumnAsync(db, "RestaurantSettings", "WelcomeText", "ALTER TABLE RestaurantSettings ADD COLUMN WelcomeText TEXT NOT NULL DEFAULT 'أهلاً بك'");
        await EnsureColumnAsync(db, "RestaurantSettings", "OnboardingJson", "ALTER TABLE RestaurantSettings ADD COLUMN OnboardingJson TEXT NULL");
        await EnsureColumnAsync(db, "RestaurantSettings", "HomeBannersJson", "ALTER TABLE RestaurantSettings ADD COLUMN HomeBannersJson TEXT NULL");
        await EnsureColumnAsync(db, "RestaurantSettings", "SplashBackground1Url", "ALTER TABLE RestaurantSettings ADD COLUMN SplashBackground1Url TEXT NULL");
        await EnsureColumnAsync(db, "RestaurantSettings", "SplashBackground2Url", "ALTER TABLE RestaurantSettings ADD COLUMN SplashBackground2Url TEXT NULL");
        await EnsureColumnAsync(db, "RestaurantSettings", "RoutingProfile", "ALTER TABLE RestaurantSettings ADD COLUMN RoutingProfile TEXT NOT NULL DEFAULT 'driving'");

        // RestaurantSettings: Driver ETA speed settings
        await EnsureColumnAsync(db, "RestaurantSettings", "DriverSpeedBikeKmH", "ALTER TABLE RestaurantSettings ADD COLUMN DriverSpeedBikeKmH TEXT NOT NULL DEFAULT 18");
        await EnsureColumnAsync(db, "RestaurantSettings", "DriverSpeedCarKmH", "ALTER TABLE RestaurantSettings ADD COLUMN DriverSpeedCarKmH TEXT NOT NULL DEFAULT 30");

        // RestaurantSettings: سعر التوصيل لكل كيلومتر
        await EnsureColumnAsync(db, "RestaurantSettings", "DeliveryFeePerKm", "ALTER TABLE RestaurantSettings ADD COLUMN DeliveryFeePerKm REAL NOT NULL DEFAULT 0");

        // RestaurantSettings cache version
        await EnsureColumnAsync(db, "RestaurantSettings", "UpdatedAtUtc", "ALTER TABLE RestaurantSettings ADD COLUMN UpdatedAtUtc TEXT NOT NULL DEFAULT (datetime('now'))");

        // RestaurantSettings: printer assignment (main, sub1, sub2 + category per sub)
        await EnsureColumnAsync(db, "RestaurantSettings", "PrinterSettingsJson", "ALTER TABLE RestaurantSettings ADD COLUMN PrinterSettingsJson TEXT NULL");

        // Categories: optional image
        await EnsureColumnAsync(db, "Categories", "ImageUrl", "ALTER TABLE Categories ADD COLUMN ImageUrl TEXT NULL");

        // Categories: activation + ordering (older DBs may not have these columns)
        await EnsureColumnAsync(db, "Categories", "IsActive", "ALTER TABLE Categories ADD COLUMN IsActive INTEGER NOT NULL DEFAULT 1");
        await EnsureColumnAsync(db, "Categories", "SortOrder", "ALTER TABLE Categories ADD COLUMN SortOrder INTEGER NOT NULL DEFAULT 0");

        // Customers: Firebase Auth fields
        await EnsureColumnAsync(db, "Customers", "FirebaseUid", "ALTER TABLE Customers ADD COLUMN FirebaseUid TEXT NULL");
        await EnsureColumnAsync(db, "Customers", "Email", "ALTER TABLE Customers ADD COLUMN Email TEXT NULL");

        // Customers: last GPS
        await EnsureColumnAsync(db, "Customers", "LastLat", "ALTER TABLE Customers ADD COLUMN LastLat REAL NOT NULL DEFAULT 0");
        await EnsureColumnAsync(db, "Customers", "LastLng", "ALTER TABLE Customers ADD COLUMN LastLng REAL NOT NULL DEFAULT 0");

        // Customers: chat blocking (admin can stop a customer from sending messages)
        await EnsureColumnAsync(db, "Customers", "IsChatBlocked", "ALTER TABLE Customers ADD COLUMN IsChatBlocked INTEGER NOT NULL DEFAULT 0");

        // Customers: app login blocking (admin can stop a customer from logging into the app)
        await EnsureColumnAsync(db, "Customers", "IsAppBlocked", "ALTER TABLE Customers ADD COLUMN IsAppBlocked INTEGER NOT NULL DEFAULT 0");

        // OrderStatusHistory: timeline metadata
        await EnsureColumnAsync(db, "OrderStatusHistory", "ChangedByType", "ALTER TABLE OrderStatusHistory ADD COLUMN ChangedByType TEXT NULL");
        await EnsureColumnAsync(db, "OrderStatusHistory", "ChangedById", "ALTER TABLE OrderStatusHistory ADD COLUMN ChangedById INTEGER NULL");
        await EnsureColumnAsync(db, "OrderStatusHistory", "ReasonCode", "ALTER TABLE OrderStatusHistory ADD COLUMN ReasonCode TEXT NULL");

        // Driver tracking: GPS accuracy
        await EnsureColumnAsync(db, "DriverLocations", "AccuracyMeters", "ALTER TABLE DriverLocations ADD COLUMN AccuracyMeters REAL NOT NULL DEFAULT 0");

        // DriverTrackPoints: attach to order for actual route + distance
        await EnsureColumnAsync(db, "DriverTrackPoints", "OrderId", "ALTER TABLE DriverTrackPoints ADD COLUMN OrderId INTEGER NULL");

        // Complaints: message idempotency key (optional)
        await EnsureColumnAsync(db, "ComplaintMessages", "FirebaseKey", "ALTER TABLE ComplaintMessages ADD COLUMN FirebaseKey TEXT NOT NULL DEFAULT ''");

        // Complaints: unread tracking
        await EnsureColumnAsync(db, "ComplaintThreads", "LastAdminSeenAtUtc", "ALTER TABLE ComplaintThreads ADD COLUMN LastAdminSeenAtUtc TEXT NULL");
        await EnsureColumnAsync(db, "ComplaintThreads", "LastCustomerSeenAtUtc", "ALTER TABLE ComplaintThreads ADD COLUMN LastCustomerSeenAtUtc TEXT NULL");

        // Helpful indexes
        await ExecAsync(db, "CREATE INDEX IF NOT EXISTS IX_ProductImages_ProductId ON ProductImages(ProductId);");
        await ExecAsync(db, "CREATE INDEX IF NOT EXISTS IX_ProductVariants_ProductId ON ProductVariants(ProductId);");
        await ExecAsync(db, "CREATE INDEX IF NOT EXISTS IX_ProductAddons_ProductId ON ProductAddons(ProductId);");

        await ExecAsync(db, "CREATE UNIQUE INDEX IF NOT EXISTS IX_Ratings_OrderId ON Ratings(OrderId);");
        await ExecAsync(db, "CREATE INDEX IF NOT EXISTS IX_Ratings_DriverId ON Ratings(DriverId);");

        // Ratings: restaurant rating fields (added later)
        await EnsureColumnAsync(db, "Ratings", "RestaurantStars", "ALTER TABLE Ratings ADD COLUMN RestaurantStars INTEGER NULL");
        await EnsureColumnAsync(db, "Ratings", "RestaurantComment", "ALTER TABLE Ratings ADD COLUMN RestaurantComment TEXT NULL");

        await ExecAsync(db, "CREATE UNIQUE INDEX IF NOT EXISTS IX_DeviceTokens_FcmToken ON DeviceTokens(FcmToken);");
        await ExecAsync(db, "CREATE INDEX IF NOT EXISTS IX_DeviceTokens_User ON DeviceTokens(UserType,UserId);");

        await ExecAsync(db, "CREATE UNIQUE INDEX IF NOT EXISTS IX_Customers_FirebaseUid ON Customers(FirebaseUid);");

        await ExecAsync(db, "CREATE INDEX IF NOT EXISTS IX_Orders_IdempotencyKey ON Orders(IdempotencyKey);");

        await ExecAsync(db, "CREATE INDEX IF NOT EXISTS IX_DriverTrackPoints_OrderId ON DriverTrackPoints(OrderId);");

        // Products availability
        await EnsureColumnAsync(db, "Products", "IsAvailable", "ALTER TABLE Products ADD COLUMN IsAvailable INTEGER NOT NULL DEFAULT 1");
        await ExecAsync(db, "CREATE INDEX IF NOT EXISTS IX_Products_IsAvailable ON Products(IsAvailable);");

        // DriverTrackPoints helpful indexes
        await ExecAsync(db, "CREATE INDEX IF NOT EXISTS IX_DriverTrackPoints_DriverId_CreatedAt ON DriverTrackPoints(DriverId,CreatedAtUtc);");
        await ExecAsync(db, "CREATE INDEX IF NOT EXISTS IX_DriverTrackPoints_OrderId_CreatedAt ON DriverTrackPoints(OrderId,CreatedAtUtc);");
    }

    private static async Task EnsureTableAsync(AppDbContext db, string table, string createSql)
    {
        // Use DbCommand directly (SQLite provider returns -1 for SELECT via ExecuteSqlRawAsync).
        await using var conn = db.Database.GetDbConnection();
        if (conn.State != System.Data.ConnectionState.Open)
            await conn.OpenAsync();

        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT name FROM sqlite_master WHERE type='table' AND name=$name";
        var p = cmd.CreateParameter();
        p.ParameterName = "$name";
        p.Value = table;
        cmd.Parameters.Add(p);
        var result = await cmd.ExecuteScalarAsync();
        if (result == null)
            await ExecAsync(db, createSql);
    }

    private static async Task EnsureColumnAsync(AppDbContext db, string table, string column, string alterSql)
    {
        await using var conn = db.Database.GetDbConnection();
        if (conn.State != System.Data.ConnectionState.Open)
            await conn.OpenAsync();

        await using var cmd = conn.CreateCommand();
        cmd.CommandText = $"PRAGMA table_info({table});";
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            var name = reader.GetString(1);
            if (string.Equals(name, column, StringComparison.OrdinalIgnoreCase))
                return;
        }
        await ExecAsync(db, alterSql);
    }

    private static Task ExecAsync(AppDbContext db, string sql)
        => db.Database.ExecuteSqlRawAsync(sql);
}