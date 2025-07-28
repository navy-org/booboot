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

const FileWrapper = @import("./file.zig").Wrapper;

pub const Config = struct {
    cfg: std.json.Parsed(Schema),

    pub const Entry = struct {
        name: []const u8,
        kernel: []const u8,
        protocol: []const u8 = "handover",
        cmdline: ?[]const u8 = null,
        modules: ?[][]const u8 = null,
    };

    const Schema = struct {
        default: ?[]const u8 = null,
        verbose: bool = false,
        entries: []Entry,
    };

    pub fn deinit(self: Config) void {
        self.cfg.deinit();
    }

    pub fn isVerbose(self: Config) bool {
        return self.cfg.value.verbose;
    }

    pub fn fromFile(file: *uefi.protocol.File) !Config {
        defer file.close() catch {};

        const sz = try file.getInfoSize(.file);

        const info_buffer = try uefi.pool_allocator.alloc(u8, sz);
        defer uefi.pool_allocator.free(info_buffer);

        const info = try file.getInfo(.file, @alignCast(info_buffer));
        const file_content = try uefi.pool_allocator.alloc(u8, info.file_size);

        _ = try file.read(file_content);

        const cfg = try std.json.parseFromSlice(Schema, uefi.pool_allocator, file_content, .{});

        return .{ .cfg = cfg };
    }

    pub fn getDefault(self: Config) !Entry {
        if (self.cfg.value.default == null) {
            return self.cfg.value.entries[0];
        }

        for (self.cfg.value.entries) |e| {
            if (std.mem.eql(u8, e.name, self.cfg.value.default.?)) {
                return e;
            }
        }

        return error.LoaderDefaultEntryNotFound;
    }
};
