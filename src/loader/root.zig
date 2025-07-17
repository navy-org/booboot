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
const paging = @import("arch").paging;
const uefi = std.os.uefi;

const logger = @import("./logger.zig");
const file = @import("./file.zig");
const Config = @import("./config.zig").Config;
const loader = @import("./loader.zig");
const utils = @import("./utils.zig");
const applyProtocol = @import("./protocols/root.zig").applyProtocol;

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = logger.log,
};

pub fn assert(ok: bool, ret: usize) void {
    if (!ok) {
        const img = file.image() catch @panic("");
        std.log.debug("Failed at {x}({x})", .{ ret, ret - @intFromPtr(img.image_base) });
        unreachable;
    }
}

fn allocateStack(sz: usize) ![]align(std.heap.pageSize()) u8 {
    var pages: [*]align(std.heap.pageSize()) u8 = undefined;
    const len = std.mem.alignForward(usize, sz, std.heap.pageSize());

    try uefi.system_table.boot_services.?._allocatePages(
        .any,
        .loader_data,
        len / std.heap.pageSize(),
        @ptrCast(&pages),
    ).err();

    @memset(pages[0..sz], 0);

    return pages[0..sz];
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    std.log.err("Zig panic! {s}", .{msg});
    const img = file.image() catch @panic("couldn't get efi image");
    std.log.err("main address {x}", .{@intFromPtr(img.image_base)});

    if (ret_addr) |addr| {
        std.log.err("Return address: {x} ({x})", .{ addr, addr - @intFromPtr(img.image_base) });
    }

    std.log.err("Stack trace:", .{});

    var iter = std.debug.StackIterator.init(ret_addr orelse @returnAddress(), null);
    defer iter.deinit();

    while (iter.next()) |address| {
        std.log.err("    * 0x{x:0>16}", .{address});
    }

    while (true) {}
}

pub fn main() void {
    const cfgFile = file.openFile("loader.json") catch |e| {
        std.log.err("couldn't open loader.json {any}", .{e});
        return;
    };

    const cfg = Config.fromFile(cfgFile) catch |e| {
        std.log.err("couldn't read or parse loader.json {any}", .{e});
        return;
    };

    paging.init(file.image() catch {
        unreachable;
    }) catch |e| {
        std.log.err("couldn't initiate paging {any}", .{e});
        uefi.system_table.boot_services.?.stall(5 * 1000 * 1000) catch {};
        return;
    };

    const entry = cfg.getDefault() catch |e| {
        std.log.err("couldn't find default entry {any}", .{e});
        uefi.system_table.boot_services.?.stall(5 * 1000 * 1000) catch {};
        return;
    };

    const hdr = loader.loadBinary(entry.path) catch |e| {
        std.log.err("couldn't load kernel file {any}", .{e});
        uefi.system_table.boot_services.?.stall(5 * 1000 * 1000) catch {};
        return;
    };

    const mods = loader.loadModules(entry.modules) catch |e| {
        std.log.err("couldn't load modules {any}", .{e});
        uefi.system_table.boot_services.?.stall(5 * 1000 * 1000) catch {};
        return;
    };

    _ = mods;

    const stack = allocateStack(utils.kib(16)) catch |e| {
        std.log.err("couldn't allocate stack: {any}", .{e});
        uefi.system_table.boot_services.?.stall(5 * 1000 * 1000) catch {};
        return;
    };

    std.log.info("loading {s}", .{entry.label});

    applyProtocol(
        entry.protocol,
        hdr,
        stack,
    ) catch |e| {
        std.log.err("couldn't get boot protocol: {any}", .{e});
        uefi.system_table.boot_services.?.stall(5 * 1000 * 1000) catch {};
        return;
    };
}
