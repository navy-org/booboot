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
const handover = @import("handover");
const uefi = std.os.uefi;

pub const MapFlag = @import("flags").MapFlag;
pub var root_page: Space = undefined;

const pSize: usize = std.heap.pageSize();
const ONE_GIB = 1 * 1024 * 1024 * 1024;

pub const Space = struct {
    root: [*]u64,

    const PageField = struct {
        const present: u64 = 1 << 0;
        const writable: u64 = 1 << 1;
        const user: u64 = 1 << 2;
        const writeThrough: u64 = 1 << 3;
        const no_cache: u64 = 1 << 4;
        const accessed: u64 = 1 << 5;
        const dirty: u64 = 1 << 6;
        const huge: u64 = 1 << 7;
        const global: u64 = 1 << 8;
        const noExecute: u64 = 1 << 63;
    };

    fn translateFlags(flags: u8) u64 {
        var f: u64 = Space.PageField.present | Space.PageField.noExecute;

        if (flags & MapFlag.none == MapFlag.none) {
            return 0;
        }

        if (flags & MapFlag.read == MapFlag.read) {}

        if (flags & MapFlag.write == MapFlag.write) {
            f |= Space.PageField.writable;
        }

        if (flags & MapFlag.execute == MapFlag.execute) {
            f &= ~Space.PageField.noExecute;
        }

        if (flags & MapFlag.user == MapFlag.user) {
            f |= Space.PageField.user;
        }

        if (flags & MapFlag.huge == MapFlag.huge) {
            f |= Space.PageField.huge;
        }

        return f;
    }

    pub fn blank() !Space {
        var page: [*]align(4096) u8 = undefined;

        try uefi.system_table.boot_services.?._allocatePages(
            .any,
            .loader_data,
            1,
            @ptrCast(&page),
        ).err();

        @memset(page[0..std.heap.pageSize()], 0);

        return .{
            .root = @alignCast(@ptrCast(page)),
        };
    }

    pub fn deinit(self: *Space) !void {
        try uefi.system_table.boot_services.?._freePages(
            @alignCast(@ptrCast(self.root)),
            1,
        ).err();
    }

    fn getEntryIndex(virt: u64, comptime level: u8) u64 {
        const shift: u64 = 12 + level * 9;
        return (virt & (0x1ff << shift)) >> shift;
    }

    fn getEntryAddr(addr: u64) u64 {
        return addr & 0x000ffffffffff000;
    }

    fn getEntry(self: Space, index: usize, alloc: bool) !Space {
        if (self.root[index] & Space.PageField.present == Space.PageField.present) {
            return .{
                .root = @ptrFromInt(Space.getEntryAddr(self.root[index])),
            };
        }

        if (!alloc) {
            return error.PageNotFound;
        }

        const page = try Space.blank();
        self.root[index] = @intFromPtr(page.root) | Space.PageField.present | Space.PageField.writable | Space.PageField.user;
        return page;
    }

    pub fn mapPage(self: Space, virt: u64, phys: u64, flags: u64) !void {
        std.debug.assert(virt % std.heap.pageSize() == 0);
        std.debug.assert(phys % std.heap.pageSize() == 0);

        const pml4Index = Space.getEntryIndex(virt, 3);
        const pml3Index = Space.getEntryIndex(virt, 2);
        const pml2Index = Space.getEntryIndex(virt, 1);
        const pml1Index = Space.getEntryIndex(virt, 0);

        var pml3 = try self.getEntry(pml4Index, true);

        if (flags & Space.PageField.huge == Space.PageField.huge and pSize == ONE_GIB) {
            pml3.root[pml3Index] = phys | flags;
            return;
        }

        var pml2 = try pml3.getEntry(pml3Index, true);
        if (flags & Space.PageField.huge == Space.PageField.huge) {
            pml2.root[pml2Index] = phys | flags;
            return;
        }

        var pml1 = try pml2.getEntry(pml2Index, true);
        pml1.root[pml1Index] = phys | flags;
    }

    pub fn map(self: Space, virt: u64, phys: u64, len: u64, flags: u8) !void {
        const _align: usize = if (flags & MapFlag.huge == MapFlag.huge) pSize else std.heap.pageSize();

        const aligned_virt = std.mem.alignBackward(u64, virt, _align);
        const aligned_phys = std.mem.alignBackward(u64, phys, _align);
        const aligned_len = std.mem.alignForward(u64, len, _align);

        const f = Space.translateFlags(flags);

        var i: usize = 0;
        while (i < aligned_len) : (i += _align) {
            try self.mapPage(aligned_virt + i, aligned_phys + i, f);
        }
    }
};

pub fn init(image: *uefi.protocol.LoadedImage) !void {
    if (uefi.system_table.boot_services == null) {
        return error.BootServicesUnavailable;
    }

    root_page = try .blank();
    errdefer root_page.deinit() catch @panic("failed to free address space");

    std.log.debug("mapping boot-agent image...", .{});
    try root_page.map(
        @intFromPtr(image.image_base),
        @intFromPtr(image.image_base),
        image.image_size,
        MapFlag.read | MapFlag.write | MapFlag.execute,
    );

    std.log.debug("mapping first 4Gib of memory...", .{});
    try root_page.map(
        handover.UPPER_HALF + std.heap.pageSize(),
        std.heap.pageSize(),
        (4 * ONE_GIB) - std.heap.pageSize(),
        MapFlag.read | MapFlag.write,
    );
}

pub fn root() Space {
    return root_page;
}
