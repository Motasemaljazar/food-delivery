namespace AdminDashboard.Entities;

public enum DriverStatus
{
    Available = 0,
    Busy = 1,
    Offline = 2
}

public enum VehicleType
{
    Bike = 0,
    Car = 1
}

public enum OrderStatus
{
    New = 0,
    Confirmed = 1,
    Preparing = 2,
    ReadyForPickup = 3,
    WithDriver = 4,
    Delivered = 5,
    Cancelled = 6
    ,
    // Driver accepted the assigned order (قبل استلام الطلب من المطعم)
    Accepted = 7
}

public enum DeliveryFeeType
{
    Fixed = 0,
    ByZone = 1
}

