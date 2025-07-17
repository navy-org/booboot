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
const file = @import("./file.zig");
const utils = @import("./utils.zig");

pub fn loadBinary(path: []const u8) !std.elf.Header {
    const elf = try file.openFile(path);
    defer elf.file.close() catch @panic("failed to close binary file");

    const hdr = try std.elf.Header.read(elf);
    var phdrs = hdr.program_header_iterator(elf);

    while (try phdrs.next()) |phdr| {
        if (hdr.is_64) {} else {
            return error.NotSupported32Bits;
        }

        if (phdr.p_type == std.elf.PT_LOAD) {
            std.log.debug("loading segment between 0x{x:0>16} & 0x{x:0>16}", .{
                phdr.p_vaddr,
                phdr.p_vaddr + phdr.p_memsz,
            });

            var pages: [*]align(std.heap.pageSize()) u8 = undefined;
            const len = std.mem.alignForward(
                usize,
                phdr.p_memsz,
                std.heap.pageSize(),
            );
            try uefi.system_table.boot_services.?._allocatePages(
                .any,
                .loader_data,
                len / std.heap.pageSize(),
                @ptrCast(&pages),
            ).err();
            @memset(pages[0..len], 0);

            errdefer uefi.system_table.boot_services.?._freePages(
                @ptrCast(pages),
                len / std.heap.pageSize(),
            ).err() catch @panic("failed to free pages");

            try paging.root().map(
                phdr.p_vaddr,
                @intFromPtr(pages),
                len,
                paging.MapFlag.read | paging.MapFlag.write | paging.MapFlag.execute,
            );

            try elf.seekableStream().seekTo(phdr.p_offset);
            _ = try elf.deprecatedReader().read(pages[0..phdr.p_filesz]);
            @memset(pages[phdr.p_filesz..phdr.p_memsz], 0);
        }
    }

    return hdr;
}

pub fn loadModules(modules: [][]const u8) !std.ArrayList([]u8) {
    var modAddr = std.ArrayList([]u8).init(uefi.pool_allocator);
    errdefer {
        for (modAddr.items) |mod| {
            std.os.uefi.pool_allocator.free(mod);
        }

        modAddr.deinit();
    }

    for (modules) |mod| {
        var f = try file.openFile(mod);
        defer f.file.close() catch @panic("couldn't close module file");

        try modAddr.append(
            try f.deprecatedReader().readAllAlloc(uefi.pool_allocator, utils.gib(4)),
        );
    }

    return modAddr;
}

pub fn deinit(info: uefi.tables.MemoryMapInfo) !void {
    try uefi.system_table.boot_services.?.exitBootServices(
        uefi.handle,
        info.key,
    );
}

pub fn mmapSnapshot() !uefi.tables.MemoryMapSlice {
    const info = try uefi.system_table.boot_services.?.getMemoryMapInfo();

    const mem = try uefi.system_table.boot_services.?.allocatePool(
        .boot_services_data,
        (info.len + 2) * info.descriptor_size,
    );

    return try uefi.system_table.boot_services.?.getMemoryMap(mem);
}
