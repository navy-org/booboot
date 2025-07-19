// Booboot - The scawy bootloaderrr
// Copyright (C) 2025   Keyb <contact@keyb.moe>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

const std = @import("std");

pub const KERNEL_BASE: usize = if (@bitSizeOf(usize) == 64) 0xffffffff80000000 else 0xc0000000;
pub const UPPER_HALF: usize = if (@bitSizeOf(usize) == 64) 0xffff800000000000 else 0xc0000000;
pub const SECTION_NAME: []const u8 = ".handover";

pub const Tags = enum(c_ulong) {
    FREE = 0x00000000,
    MAGIC = 0xc001b001,
    SELF = 0xa24f988d,
    STACK = 0xf65b391b,
    KERNEL = 0xbfc71b20,
    LOADER = 0xf1f80c26,
    FILE = 0xcbc36d3b,
    RSDP = 0x8ef29c18,
    FDT = 0xb628bbc1,
    FB = 0xe2d55685,
    CMDLINE = 0x435140c4,
    RESERVED = 0xb8841d2d,
    END = 0xffffffff,
};

pub const Framebuffer = extern struct {
    pub const RGBX8888: u16 = 0x7451;
    pub const BGRX8888: u16 = 0xd040;

    width: u16,
    height: u16,
    pitch: u16,
    format: u16,
};

pub const File = extern struct {
    name: u32,
    meta: u32 = 0,
};

pub const Record = extern struct {
    tag: u32,
    flags: u32 = 0,
    start: u64 = 0,
    size: u64 = 0,
    content: extern union { fb: Framebuffer, file: File, misc: u64 } = .{
        .misc = 0,
    },

    pub fn end(self: Record) usize {
        return self.start + self.size;
    }

    pub fn isJustAfter(self: Record, other: Record) bool {
        return self.start == other.end();
    }

    pub fn isJustBefore(self: Record, other: Record) bool {
        return self.end() == other.start;
    }

    pub fn overlapsWith(self: Record, other: Record) bool {
        return self.start < other.end() and
            other.start < self.end();
    }

    pub fn contains(self: Record, other: Record) bool {
        return self.start <= other.start and other.end() <= self.end();
    }

    pub fn isMergeable(self: Record) bool {
        const tag: Tags = @enumFromInt(self.tag);
        return tag == Tags.FREE or
            tag == Tags.LOADER or
            tag == Tags.KERNEL or
            tag == Tags.RESERVED;
    }

    pub fn halfUnder(self: Record, other: Record) Record {
        if (self.overlapsWith(other) and self.start < other.start) {
            return .{
                .tag = other.tag,
                .start = self.start,
                .size = other.start - self.start,
            };
        }

        return .{ .start = 0, .size = 0, .tag = 0 };
    }

    pub fn halfOver(self: Record, other: Record) Record {
        if (self.overlapsWith(other) and
            self.end() > other.end())
        {
            return .{
                .tag = other.tag,
                .start = other.end(),
                .size = self.end() - other.end(),
            };
        }

        return .{ .start = 0, .size = 0, .tag = 0 };
    }

    pub fn print(self: Record) void {
        std.log.debug("{x} {x} -> {x}", .{ self.tag, self.start, self.start + self.size });
    }
};

pub const Payload = extern struct {
    magic: u32,
    agent: u32,
    size: u32,
    count: u32,
    records: [*c]Record,
};

pub const Request = extern struct {
    tag: u32,
    flags: u32,
    misc: u64 = 0,
};

pub const Builder = struct {
    records: std.ArrayListUnmanaged(Record),
    payload: []Payload,
    size: usize,
    buffer: []u8,
    fba: std.heap.FixedBufferAllocator,

    pub fn init(buf: []u8) !Builder {
        var fba = std.heap.FixedBufferAllocator.init(buf);
        const alloc = fba.allocator();

        return .{
            .buffer = buf,
            .size = buf.len,
            .records = .{},
            .payload = try alloc.alloc(Payload, 1),
            .fba = fba,
        };
    }

    pub fn append(self: *Builder, record: Record) !void {
        const alloc = self.fba.allocator();

        if (record.tag != @intFromEnum(Tags.MAGIC) and
            record.tag != @intFromEnum(Tags.END) and
            record.tag != @intFromEnum(Tags.CMDLINE) and record.size == 0)
        {
            return;
        }

        for (self.records.items, 0..) |other, idx| {
            if (record.tag == other.tag and
                record.isJustAfter(other) and record.isMergeable())
            {
                _ = self.records.swapRemove(idx);
                try self.append(
                    .{
                        .start = other.start,
                        .size = other.size + record.size,
                        .tag = other.tag,
                    },
                );
                return;
            }

            if (record.tag == other.tag and
                record.isJustBefore(other) and record.isMergeable())
            {
                _ = self.records.swapRemove(idx);
                try self.append(
                    .{
                        .start = other.start - record.size,
                        .size = other.size + record.size,
                        .tag = other.tag,
                    },
                );
                return;
            }

            if (record.overlapsWith(other)) {
                if ((record.isMergeable() and !other.isMergeable()) or
                    @as(Tags, @enumFromInt(other.tag)) == Tags.FREE)
                {
                    _ = self.records.swapRemove(idx);

                    const under = other.halfUnder(record);
                    const over = other.halfOver(record);

                    try self.append(other);
                    try self.append(under);
                    try self.append(over);
                    return;
                } else if (!record.isMergeable() and other.isMergeable()) {
                    _ = self.records.swapRemove(idx);

                    const under = record.halfUnder(other);
                    const over = record.halfOver(other);

                    try self.append(record);
                    try self.append(under);
                    try self.append(over);
                    return;
                } else if (record.contains(other)) {
                    _ = self.records.swapRemove(idx);
                    try self.append(record);
                } else if (other.contains(record)) {} else {
                    record.print();
                    other.print();
                    return error.HandoverRecordCollide;
                }
            }

            if (record.start < other.start) {
                try self.records.insert(alloc, idx, record);
                return;
            }
        }

        try self.records.append(alloc, record);
    }

    pub fn addString(self: *Builder, s: []const u8) u32 {
        const len = s.len + 1;
        const offset = self.size - len;
        const ptr: []u8 = self.buffer[offset .. offset + len];
        @memset(ptr, 0);

        std.mem.copyForwards(
            u8,
            ptr,
            s,
        );

        self.size -= len;

        return @intCast(offset);
    }

    pub fn finalize(self: *Builder, agent: []const u8, offset: usize) usize {
        const ptr: usize = @intFromPtr(self.records.items.ptr);

        self.payload[0].magic = @intFromEnum(Tags.MAGIC);
        self.payload[0].agent = self.addString(agent);
        self.payload[0].count = @intCast(self.records.items.len);
        self.payload[0].records = @ptrFromInt(ptr + offset);
        self.payload[0].size = @intCast(self.size);

        return @intFromPtr(&self.payload[0]) + offset;
    }
};
