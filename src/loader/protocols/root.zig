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
const loader = @import("../loader.zig");
const ConfigEntry = @import("../config.zig").Config.Entry;

const Protocol = enum {
    handover,
};

pub fn applyProtocol(
    name: []const u8,
    elf: loader.ElfFile,
    stack: []align(std.heap.pageSize()) u8,
    mods: ?std.ArrayList(loader.ModFile),
    config: ConfigEntry,
) !void {
    const prot = std.meta.stringToEnum(Protocol, name) orelse {
        return error.UnknownBootProtocol;
    };

    const mod = switch (prot) {
        .handover => @import("./handover.zig"),
    };

    try mod.apply(elf, stack, mods, config);
}
