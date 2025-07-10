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
