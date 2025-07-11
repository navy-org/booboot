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

var _image: ?*uefi.protocol.LoadedImage = null;
var _fs: ?*uefi.protocol.SimpleFileSystem = null;

const EFI_BY_HANDLE_PROTOCOL = uefi.tables.OpenProtocolAttributes{ .by_handle_protocol = true };

pub fn image() !*uefi.protocol.LoadedImage {
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

pub fn fs() !*uefi.protocol.SimpleFileSystem {
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

    defer uefi.pool_allocator.free(transPath);

    std.mem.replaceScalar(u16, transPath, @intCast('/'), @intCast('\\'));
    const rootDir = try (try fs()).openVolume();
    return try rootDir.open(
        transPath,
        .read,
        .{ .read_only = true },
    );
}
