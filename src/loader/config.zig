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
