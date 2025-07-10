const std = @import("std");
const logger = @import("./logger.zig").log;
const uefi = std.os.uefi;

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logger,
};

pub fn main() void {
    std.log.info("Hello, World!", .{});
    _ = uefi.system_table.boot_services.?.stall(5 * 1000 * 1000);
}
