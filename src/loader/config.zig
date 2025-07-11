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

pub const Config = struct {
    cfg: std.json.Parsed(Schema),

    const Entry = struct {
        label: []const u8,
        path: []const u8,
        protocol: []const u8,
        cmdline: []const u8,
        modules: [][]const u8,
    };

    const Schema = struct {
        default: ?[]const u8,
        entries: []Entry,
    };

    pub fn fromFile(file: *uefi.protocol.File) !Config {
        var r = std.json.reader(uefi.pool_allocator, file.reader());
        const cfg = try std.json.parseFromTokenSource(Schema, uefi.pool_allocator, &r, .{});
        return .{ .cfg = cfg };
    }

    pub fn getDefault(self: Config) []const u8 {
        return self.cfg.value.default orelse self.cfg.value.entries[0].label;
    }
};
