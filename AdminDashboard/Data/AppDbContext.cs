using AdminDashboard.Entities;
using Microsoft.EntityFrameworkCore;

namespace AdminDashboard.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<RestaurantSettings> RestaurantSettings => Set<RestaurantSettings>();
    public DbSet<DeliveryZone> DeliveryZones => Set<DeliveryZone>();
    public DbSet<AdminUser> AdminUsers => Set<AdminUser>();
    public DbSet<Customer> Customers => Set<Customer>();
    public DbSet<CustomerAddress> CustomerAddresses => Set<CustomerAddress>();
    public DbSet<Driver> Drivers => Set<Driver>();
    public DbSet<Category> Categories => Set<Category>();
    public DbSet<Product> Products => Set<Product>();
    public DbSet<ProductImage> ProductImages => Set<ProductImage>();
    public DbSet<ProductVariant> ProductVariants => Set<ProductVariant>();
    public DbSet<ProductAddon> ProductAddons => Set<ProductAddon>();
    public DbSet<Offer> Offers => Set<Offer>();
    public DbSet<OfferProduct> OfferProducts => Set<OfferProduct>();
    public DbSet<OfferCategory> OfferCategories => Set<OfferCategory>();
    public DbSet<Discount> Discounts => Set<Discount>();
    public DbSet<Order> Orders => Set<Order>();
    public DbSet<OrderItem> OrderItems => Set<OrderItem>();
    public DbSet<OrderStatusHistory> OrderStatusHistory => Set<OrderStatusHistory>();
    public DbSet<DriverLocation> DriverLocations => Set<DriverLocation>();
    public DbSet<DriverTrackPoint> DriverTrackPoints => Set<DriverTrackPoint>();
    public DbSet<Rating> Ratings => Set<Rating>();
    public DbSet<OrderRating> OrderRatings => Set<OrderRating>();
    public DbSet<ComplaintThread> ComplaintThreads => Set<ComplaintThread>();
    public DbSet<ComplaintMessage> ComplaintMessages => Set<ComplaintMessage>();
    public DbSet<Notification> Notifications => Set<Notification>();
    public DbSet<DeviceToken> DeviceTokens => Set<DeviceToken>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<Customer>().HasIndex(x => x.Phone).IsUnique();
        b.Entity<Driver>().HasIndex(x => x.Phone).IsUnique();

        b.Entity<CustomerAddress>().HasIndex(x => new { x.CustomerId, x.IsDefault });
        b.Entity<CustomerAddress>()
            .HasOne(x => x.Customer)
            .WithMany()
            .HasForeignKey(x => x.CustomerId)
            .OnDelete(DeleteBehavior.Cascade);

        b.Entity<Order>().HasIndex(x => x.CreatedAtUtc);
        b.Entity<Order>().HasIndex(x => x.CurrentStatus);
        b.Entity<Order>().HasIndex(x => x.IdempotencyKey);

        b.Entity<OrderItem>()
            .HasOne(x => x.Order)
            .WithMany(x => x.Items)
            .HasForeignKey(x => x.OrderId)
            .OnDelete(DeleteBehavior.Cascade);

        b.Entity<OrderStatusHistory>()
            .HasOne(x => x.Order)
            .WithMany(x => x.StatusHistory)
            .HasForeignKey(x => x.OrderId)
            .OnDelete(DeleteBehavior.Cascade);

        b.Entity<ProductImage>()
            .HasOne(x => x.Product)
            .WithMany(x => x.Images)
            .HasForeignKey(x => x.ProductId)
            .OnDelete(DeleteBehavior.Cascade);

        b.Entity<ProductVariant>()
            .HasOne(x => x.Product)
            .WithMany(p => p.Variants)
            .HasForeignKey(x => x.ProductId)
            .OnDelete(DeleteBehavior.Cascade);

        b.Entity<ProductAddon>()
            .HasOne(x => x.Product)
            .WithMany(p => p.Addons)
            .HasForeignKey(x => x.ProductId)
            .OnDelete(DeleteBehavior.Cascade);

        b.Entity<ProductVariant>().HasIndex(x => new { x.ProductId, x.SortOrder });
        b.Entity<ProductAddon>().HasIndex(x => new { x.ProductId, x.SortOrder });

        b.Entity<DriverLocation>().HasIndex(x => x.DriverId).IsUnique();

        b.Entity<DriverTrackPoint>().HasIndex(x => new { x.DriverId, x.CreatedAtUtc });

        b.Entity<Notification>().HasIndex(x => new { x.UserType, x.UserId, x.CreatedAtUtc });

        b.Entity<DeviceToken>().HasIndex(x => x.FcmToken).IsUnique();
        b.Entity<DeviceToken>().HasIndex(x => new { x.UserType, x.UserId });

        b.Entity<DeliveryZone>().HasIndex(x => new { x.IsActive, x.SortOrder });

        b.Entity<ComplaintMessage>()
            .HasOne(x => x.Thread)
            .WithMany(x => x.Messages)
            .HasForeignKey(x => x.ThreadId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
