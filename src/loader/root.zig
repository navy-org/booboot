const uefi = @import("std").os.uefi;
const writer = @import("./logger.zig").uefiWriter;

pub fn main() void {
    _ = writer.print("Hello, World!", .{}) catch {};
    _ = uefi.system_table.boot_services.?.stall(5 * 1000 * 1000);
}
