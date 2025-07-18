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
const kib = @import("../utils.zig").kib;
const paging = @import("arch").paging;

const loader = @import("../loader.zig");
const handover = @import("handover");

pub fn apply(hdr: std.elf.Header, stack: []align(std.heap.pageSize()) u8) !void {
    std.log.debug("applying handover protocol", .{});
    var buffer: [*]align(std.heap.pageSize()) u8 = undefined;

    try uefi.system_table.boot_services.?._allocatePages(
        .any,
        .loader_data,
        kib(16) / std.heap.pageSize(),
        @ptrCast(&buffer),
    ).err();

    errdefer _ = uefi.system_table.boot_services.?._freePages(
        @ptrCast(buffer),
        kib(16) / std.heap.pageSize(),
    );

    @memset(buffer[0..kib(16)], 0);

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

    std.log.debug("Jump to ip: {x}, cr3: {x}", .{ hdr.entry, @intFromPtr(paging.root_page.root) });

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
          [entry] "r" (hdr.entry),
          [stack] "r" (@intFromPtr(stack.ptr) + stack.len + handover.UPPER_HALF),
          [payload] "{rsi}" (ptr),
          [magic] "{rdi}" (@intFromEnum(handover.Tags.MAGIC)),
        : "cr3", "memory"
    );
}
