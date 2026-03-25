using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AdminDashboard.Migrations
{
    /// <inheritdoc />
    public partial class AddOrderTypeToOrders : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "OrderType",
                table: "Orders",
                type: "varchar(20)",
                maxLength: 20,
                nullable: true);

            //تم الطلبات الحالية: من لديه (0,0) نعيّن له pickup وإلا delivery
            migrationBuilder.Sql(@"
                UPDATE Orders SET OrderType = IF(DeliveryLat = 0 AND DeliveryLng = 0, 'pickup', 'delivery') WHERE OrderType IS NULL;
            ");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "OrderType",
                table: "Orders");
        }
    }
}
