const std = @import("std");
const uefi = std.os.uefi;

const logger = @import("./logger.zig").log;
const openFile = @import("./file.zig").openFile;
const Config = @import("./config.zig").Config;

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logger,
};

pub fn main() void {
    const cfgFile = openFile("loader.json") catch |e| {
        std.log.err("Couldn't open loader.json {any}", .{e});
        _ = uefi.system_table.boot_services.?.stall(5 * 1000 * 1000);
        return;
    };

    const cfg = Config.fromFile(cfgFile) catch |e| {
        std.log.err("Couldn't read or parse loader.json {any}", .{e});
        _ = uefi.system_table.boot_services.?.stall(5 * 1000 * 1000);
        return;
    };

    std.log.info("Loading {s}", .{cfg.getDefault()});
    _ = uefi.system_table.boot_services.?.stall(5 * 1000 * 1000);
}
