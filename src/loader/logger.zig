const std = @import("std");
const uefi = std.os.uefi;

fn uefiWriteOpaque(_: *const anyopaque, bytes: []const u8) !usize {
    const utf16Str = try std.unicode.utf8ToUtf16LeAllocZ(uefi.pool_allocator, bytes);
    defer uefi.pool_allocator.free(utf16Str);

    if (uefi.system_table.con_out) |cout| {
        _ = try cout.outputString(utf16Str);
    }

    return bytes.len;
}

pub const uefiWriter = std.io.AnyWriter{ .context = @ptrFromInt(0xdeadbeef), .writeFn = uefiWriteOpaque };

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
