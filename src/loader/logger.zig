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

fn uefiWriteOpaque(_: *const anyopaque, bytes: []const u8) !usize {
    for (bytes) |b| {
        if (uefi.system_table.con_out) |cout| {
            const s: [2:0]u16 = .{ @intCast(b), 0 };
            _ = try cout.outputString(&s);
        }
    }

    return bytes.len;
}

const uefiWriter: std.io.AnyWriter = .{
    .context = @ptrFromInt(0xdeadbeef),
    .writeFn = uefiWriteOpaque,
};

pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (uefi.system_table.con_out) |cout| {
        const color = comptime switch (level) {
            .debug => .blue,
            .info => .green,
            .warn => .yellow,
            .err => .red,
        };

        const text = comptime switch (level) {
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
        };

        const prefix = if (scope != .default) @tagName(scope) else "";
        cout.setAttribute(.{ .foreground = color }) catch {};

        uefiWriter.print("{s: >6}", .{text}) catch {};
        cout.setAttribute(.{ .foreground = .white }) catch {};
        uefiWriter.print("{s: <7}", .{prefix}) catch {};
        uefiWriter.print(format, args) catch {};
        uefiWriter.print("\r\n", .{}) catch {};
    }
}
