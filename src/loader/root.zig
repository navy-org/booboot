// Booboot - The scawy bootloaderrr
// Copyright (C) 2025   Keyb <contact@keyb.moe>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

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
