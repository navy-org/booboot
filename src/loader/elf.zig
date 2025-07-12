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

const file = @import("./file.zig");

pub fn loadBinary(path: []const u8) !void {
    const elf = try file.openFile(path);
    const hdr = try std.elf.Header.read(elf);
    const phdr = hdr.program_header_iterator(elf);
    _ = phdr;

    if (hdr.is_64) {} else {
        return error.NotSupported32Bits;
    }
}
