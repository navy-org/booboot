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

var mmap_key: usize = 0;

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
            try uefi.system_table.boot_services.?.allocatePages(
                uefi.tables.AllocateType.allocate_any_pages,
                uefi.tables.MemoryType.loader_data,
                len / std.heap.pageSize(),
                &pages,
            ).err();
            @memset(pages[0..len], 0);

            errdefer uefi.system_table.boot_services.?.freePages(
                pages,
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

pub fn deinit() !void {
    try uefi.system_table.boot_services.?.exitBootServices(
        uefi.handle,
        mmap_key,
    ).err();
}

pub fn mmapSnapshot() ![]uefi.tables.MemoryDescriptor {
    var mmap_size: usize = 0;
    var descriptor_size: usize = 0;
    var descriptor_version: u32 = 0;
    var mmap: ?[*]uefi.tables.MemoryDescriptor = undefined;

    if (uefi.system_table.boot_services.?.getMemoryMap(
        &mmap_size,
        mmap,
        &mmap_key,
        &descriptor_size,
        &descriptor_version,
    ) != .buffer_too_small) {
        return error.ExpectedBufferTooSmall;
    }

    mmap_size += 2 * descriptor_size;
    var mem: [*]align(8) u8 = undefined;
    try uefi.system_table.boot_services.?.allocatePool(
        .boot_services_data,
        mmap_size,
        &mem,
    ).err();
    mmap = @ptrCast(@alignCast(mem));

    try uefi.system_table.boot_services.?.getMemoryMap(
        &mmap_size,
        mmap,
        &mmap_key,
        &descriptor_size,
        &descriptor_version,
    ).err();

    return mmap.?[0..(mmap_size / descriptor_size)];
}
