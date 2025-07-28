// Booboot - The mischievous bootloaderrr
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
const elf = std.elf;

const paging = @import("arch").paging;
const file = @import("./file.zig");
const utils = @import("./utils.zig");

pub const ElfFile = struct {
    hdr: std.elf.Header,
    content: []u8,
};

pub const ModFile = struct {
    filename: []const u8,
    content: []u8,
};

pub fn loadBinary(path: []const u8) !ElfFile {
    const f = try file.openFile(path);
    defer f.close() catch {};

    const sz = try f.getInfoSize(.file);
    const info_buffer = try uefi.pool_allocator.alloc(u8, sz);
    defer uefi.pool_allocator.free(info_buffer);

    const info = try f.getInfo(.file, @alignCast(info_buffer));
    const file_content = try uefi.pool_allocator.alloc(u8, info.file_size);

    _ = try f.read(file_content);

    if (!std.mem.eql(u8, file_content[0..4], elf.MAGIC)) return error.InvalidElfMagic;
    if (file_content[elf.EI_VERSION] != 1) return error.InvalidElfVersion;

    const endian: std.builtin.Endian = switch (file_content[elf.EI_DATA]) {
        elf.ELFDATA2LSB => .little,
        elf.ELFDATA2MSB => .big,
        else => return error.InvalidElfEndian,
    };

    if (file_content[elf.EI_CLASS] == elf.ELFCLASS32) {
        return error.NotSupported32Bits;
    }

    const ehdr: *std.elf.Elf64_Ehdr = @alignCast(std.mem.bytesAsValue(elf.Elf64_Ehdr, file_content));
    const hdr = std.elf.Header.init(ehdr.*, endian);

    const phdrs: []std.elf.Phdr = @as([*]std.elf.Phdr, @ptrFromInt(@intFromPtr(file_content.ptr) + hdr.phoff))[0..hdr.phnum];

    for (phdrs) |phdr| {
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

            std.mem.copyForwards(u8, pages[0..phdr.p_filesz], file_content[phdr.p_offset .. phdr.p_offset + phdr.p_filesz]);
            @memset(pages[phdr.p_filesz..phdr.p_memsz], 0);
        }
    }

    return .{ .hdr = hdr, .content = file_content };
}

pub fn loadSection(name: []const u8, bin: ElfFile, T: type) !?[]align(1) T {
    const shdrs: []std.elf.Shdr = @as([*]elf.Shdr, @ptrFromInt(@intFromPtr(bin.content.ptr) + bin.hdr.shoff))[0..bin.hdr.shnum];
    const shstr = shdrs[bin.hdr.shstrndx];

    for (shdrs) |shdr| {
        const other = try uefi.pool_allocator.alloc(u8, name.len);
        defer uefi.pool_allocator.free(other);

        const offset = shstr.sh_offset + shdr.sh_name;
        std.mem.copyForwards(u8, other, bin.content[offset .. offset + other.len]);

        if (std.mem.eql(u8, other, name)) {
            const section_data = try uefi.pool_allocator.alloc(u8, shdr.sh_size);
            std.mem.copyForwards(u8, section_data, bin.content[shdr.sh_offset .. shdr.sh_offset + section_data.len]);
            return std.mem.bytesAsSlice(T, section_data);
        }
    }

    return null;
}

pub fn loadModules(modules: [][]const u8) !std.ArrayList(ModFile) {
    var mods = std.ArrayList(ModFile).init(uefi.pool_allocator);
    errdefer {
        for (mods.items) |mod| {
            std.os.uefi.pool_allocator.free(mod.content);
        }

        mods.deinit();
    }

    for (modules) |mod| {
        var f = try file.openFile(mod);
        defer f.close() catch @panic("couldn't close module file");

        const sz = try f.getInfoSize(.file);
        const info_buffer = try uefi.pool_allocator.alloc(u8, sz);
        defer uefi.pool_allocator.free(info_buffer);

        const info = try f.getInfo(.file, @alignCast(info_buffer));
        const file_content = try uefi.pool_allocator.alloc(u8, info.file_size);
        _ = try f.read(file_content);

        try mods.append(
            .{
                .filename = mod,
                .content = file_content,
            },
        );
    }

    return mods;
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

pub fn framebuffer() !*uefi.protocol.GraphicsOutput.Mode {
    const gop: ?*uefi.protocol.GraphicsOutput = try uefi.system_table.boot_services.?.locateProtocol(
        uefi.protocol.GraphicsOutput,
        null,
    );

    if (gop) |g| {
        _ = try g.queryMode(g.mode.max_mode - 1);
        try g.setMode(g.mode.max_mode - 1);

        return g.mode;
    } else {
        return error.CouldntGetFramebuffer;
    }
}

pub fn findAcpi() !usize {
    var acpi2Ptr: ?usize = null;
    var acpi1Ptr: ?usize = null;

    for (0..uefi.system_table.number_of_table_entries) |i| {
        const table = uefi.system_table.configuration_table[i];
        if (table.vendor_guid.eql(uefi.tables.ConfigurationTable.acpi_10_table_guid)) {
            acpi1Ptr = @intFromPtr(table.vendor_table);
        }

        if (table.vendor_guid.eql(uefi.tables.ConfigurationTable.acpi_20_table_guid)) {
            acpi2Ptr = @intFromPtr(table.vendor_table);
        }
    }

    if (acpi2Ptr != null) {
        return acpi2Ptr.?;
    } else if (acpi1Ptr != null) {
        return acpi1Ptr.?;
    }
    return error.CouldntFindAcpi;
}
