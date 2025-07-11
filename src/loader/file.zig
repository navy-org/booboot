const std = @import("std");
const uefi = std.os.uefi;

var _image: ?*uefi.protocol.LoadedImage = null;
var _fs: ?*uefi.protocol.SimpleFileSystem = null;

const EFI_BY_HANDLE_PROTOCOL = uefi.tables.OpenProtocolAttributes{ .by_handle_protocol = true };

fn image() !*uefi.protocol.LoadedImage {
    if (_image) |img| {
        return img;
    }

    var guid = uefi.protocol.LoadedImage.guid;

    if (uefi.system_table.boot_services) |bs| {
        try bs.openProtocol(
            uefi.handle,
            @alignCast(&guid),
            @ptrCast(&_image),
            uefi.handle,
            null,
            EFI_BY_HANDLE_PROTOCOL,
        ).err();

        return _image.?;
    } else {
        return error.BootServicesUnavailable;
    }
}

fn fs() !*uefi.protocol.SimpleFileSystem {
    if (_fs) |f| {
        return f;
    }

    var guid = uefi.protocol.SimpleFileSystem.guid;

    if ((try image()).device_handle) |hdev| {
        try uefi.system_table.boot_services.?.openProtocol(
            hdev,
            @alignCast(&guid),
            @ptrCast(&_fs),
            uefi.handle,
            null,
            EFI_BY_HANDLE_PROTOCOL,
        ).err();
    } else {
        return error.CouldntGetDeviceHandle;
    }

    return _fs.?;
}

pub fn openFile(path: []const u8) !*uefi.protocol.File {
    const transPath = try std.unicode.utf8ToUtf16LeAllocZ(
        uefi.pool_allocator,
        path,
    );

    std.mem.replaceScalar(u16, transPath, @intCast('/'), @intCast('\\'));
    const rootDir = try (try fs()).openVolume();
    return try rootDir.open(
        transPath,
        .read,
        .{ .read_only = true },
    );
}
