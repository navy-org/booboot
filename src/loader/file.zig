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
const File = uefi.protocol.File;

var _image: ?*uefi.protocol.LoadedImage = null;
var _fs: ?*uefi.protocol.SimpleFileSystem = null;

const EFI_BY_HANDLE_PROTOCOL = uefi.tables.OpenProtocolArgs{ .by_handle_protocol = .{} };

pub const Wrapper = struct {
    //! CLEAN ME: Check future EFI File API
    file: *File,

    pub fn seekableStream(self: Wrapper) std.io.SeekableStream(
        *File,
        File.SeekError,
        File.SeekError,
        File.setPosition,
        undefined,
        undefined,
        undefined,
    ) {
        return .{ .context = self.file };
    }

    pub fn deprecatedReader(self: Wrapper) std.io.GenericReader(
        *File,
        File.ReadError,
        File.read,
    ) {
        return .{ .context = self.file };
    }
};

pub fn image() !*uefi.protocol.LoadedImage {
    if (_image) |img| {
        return img;
    }

    if (uefi.system_table.boot_services) |bs| {
        _image = try bs.openProtocol(
            uefi.protocol.LoadedImage,
            uefi.handle,
            EFI_BY_HANDLE_PROTOCOL,
        );

        std.log.info("Image base: {x}", .{@intFromPtr(_image.?.image_base)});

        return _image.?;
    } else {
        return error.BootServicesUnavailable;
    }
}

pub fn fs() !*uefi.protocol.SimpleFileSystem {
    if (_fs) |f| {
        return f;
    }

    if ((try image()).device_handle) |hdev| {
        _fs = try uefi.system_table.boot_services.?.openProtocol(
            uefi.protocol.SimpleFileSystem,
            hdev,
            EFI_BY_HANDLE_PROTOCOL,
        );
    } else {
        return error.CouldntGetDeviceHandle;
    }

    return _fs.?;
}

pub fn openFile(path: []const u8) !Wrapper {
    const transPath = try std.unicode.utf8ToUtf16LeAllocZ(
        uefi.pool_allocator,
        path,
    );

    defer uefi.pool_allocator.free(transPath);

    std.mem.replaceScalar(u16, transPath, @intCast('/'), @intCast('\\'));
    const rootDir = try (try fs()).openVolume();
    return .{
        .file = try rootDir.open(
            transPath,
            .read,
            .{ .read_only = true },
        ),
    };
}
