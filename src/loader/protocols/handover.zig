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
const paging = @import("arch").paging;

const loader = @import("../loader.zig");
const kib = @import("../utils.zig").kib;
const ConfigEntry = @import("../config.zig").Config.Entry;
const handover = @import("handover");

pub fn apply(
    elf: loader.ElfFile,
    stack: []align(std.heap.pageSize()) u8,
    mods: ?std.ArrayList(loader.ModFile),
    config: ConfigEntry,
) !void {
    defer {
        if (mods) |m| {
            for (m.items) |mod| {
                uefi.pool_allocator.free(mod.content);
            }

            m.deinit();
        }
        elf.close() catch @panic("couldn't close elf file");
    }

    std.log.debug("applying handover protocol", .{});

    var buffer: [*]align(std.heap.pageSize()) u8 = undefined;
    try uefi.system_table.boot_services.?._allocatePages(
        .any,
        .loader_data,
        kib(16) / std.heap.pageSize(),
        @ptrCast(&buffer),
    ).err();
    @memset(buffer[0..kib(16)], 0);

    errdefer _ = uefi.system_table.boot_services.?._freePages(
        @ptrCast(buffer),
        kib(16) / std.heap.pageSize(),
    );

    var payload = try handover.Builder.init(buffer[0..kib(16)]);
    try payload.append(.{
        .tag = @intFromEnum(handover.Tags.MAGIC),
        .start = 0,
        .size = 0,
    });

    try payload.append(.{
        .tag = @intFromEnum(handover.Tags.SELF),
        .start = @intFromPtr(buffer),
        .size = kib(16),
    });
    try payload.append(.{
        .tag = @intFromEnum(handover.Tags.STACK),
        .start = @intFromPtr(stack.ptr),
        .size = stack.len,
    });

    const reqs = try loader.loadSection(".handover", elf, handover.Request);
    if (reqs[0].tag != @intFromEnum(handover.Tags.MAGIC)) {
        return error.HandoverRecordCorrupted;
    }

    for (reqs[1 .. reqs.len - 1]) |r| {
        switch (@as(handover.Tags, @enumFromInt(r.tag))) {
            .CMDLINE => {
                if (config.cmdline) |cmd| {
                    try payload.append(.{
                        .tag = r.tag,
                        .content = .{ .misc = payload.addString(cmd) },
                    });
                }
            },
            .FILE => {
                if (mods) |m| {
                    for (m.items) |mod| {
                        try payload.append(.{
                            .tag = r.tag,
                            .start = @intFromPtr(mod.content.ptr),
                            .size = mod.content.len,
                            .content = .{ .file = .{ .name = payload.addString(mod.filename) } },
                        });
                    }
                }
            },
            .FB => {
                const fb = try loader.framebuffer();
                try payload.append(.{
                    .tag = r.tag,
                    .start = fb.frame_buffer_base,
                    .size = fb.frame_buffer_size,
                    .content = .{ .fb = .{
                        .width = @intCast(fb.info.horizontal_resolution),
                        .height = @intCast(fb.info.vertical_resolution),
                        .pitch = @intCast(fb.info.pixels_per_scan_line * @sizeOf(u32)),
                        .format = handover.Framebuffer.BGRX8888,
                    } },
                });
            },
            .RSDP => {
                try payload.append(.{
                    .tag = r.tag,
                    .start = try loader.findAcpi(),
                    .size = std.heap.pageSize(),
                });
            },
            else => {
                std.log.warn("invalid tag {x}, skipping...", .{r.tag});
                continue;
            },
        }
    }

    std.log.debug("Jump to ip: {x}, cr3: {x}", .{ elf.hdr.entry, @intFromPtr(paging.root_page.root) });

    const mmap = try loader.mmapSnapshot();
    var it = mmap.iterator();
    while (it.next()) |m| {
        const tag: handover.Tags = switch (m.type) {
            .loader_code,
            .loader_data,
            .boot_services_code,
            .boot_services_data,
            .runtime_services_code,
            .runtime_services_data,
            => .LOADER,
            .conventional_memory => .FREE,
            else => .RESERVED,
        };

        const entry = handover.Record{
            .tag = @intFromEnum(tag),
            .start = m.physical_start,
            .size = m.number_of_pages * std.heap.pageSize(),
        };

        try payload.append(entry);
    }

    try payload.append(.{
        .tag = @intFromEnum(handover.Tags.END),
        .start = std.math.maxInt(usize),
        .size = 0,
    });

    const ptr: usize = payload.finalize("booboot", handover.UPPER_HALF);
    try loader.deinit(mmap.info);

    asm volatile (
        \\ cli
        \\ mov %[stack], %%rsp
        \\ mov $0, %%rbp
        \\ mov %[page], %%cr3
        \\ call *%[entry]
        :
        : [page] "r" (@intFromPtr(paging.root_page.root)),
          [entry] "r" (elf.hdr.entry),
          [stack] "r" (@intFromPtr(stack.ptr) + stack.len + handover.UPPER_HALF),
          [payload] "{rsi}" (ptr),
          [magic] "{rdi}" (@intFromEnum(handover.Tags.MAGIC)),
    );
}
