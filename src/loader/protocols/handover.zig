const std = @import("std");
const uefi = std.os.uefi;
const kib = @import("../utils.zig").kib;
const paging = @import("arch").paging;

const loader = @import("../loader.zig");
const handover = @import("handover");

pub fn apply(hdr: std.elf.Header, stack: []align(std.heap.pageSize()) u8) !void {
    std.log.debug("applying handover protocol", .{});
    var buffer: [*]align(std.heap.pageSize()) u8 = undefined;

    try uefi.system_table.boot_services.?.allocatePages(
        uefi.tables.AllocateType.allocate_any_pages,
        uefi.tables.MemoryType.loader_data,
        kib(16) / std.heap.pageSize(),
        &buffer,
    ).err();

    @memset(buffer[0..kib(16)], 0);

    var payload = try handover.Builder.init(buffer[0..kib(16)]);

    try payload.append(.{
        .tag = @intFromEnum(handover.Tags.MAGIC),
        .start = 0,
        .size = 0,
    });

    try payload.append(.{
        .tag = @intFromEnum(handover.Tags.SELF),
        .start = @intFromPtr(buffer),
        .size = kib(16),
    });

    try paging.root_page.map(
        @intFromPtr(stack.ptr) + handover.UPPER_HALF,
        @intFromPtr(stack.ptr),
        stack.len,
        paging.MapFlag.read | paging.MapFlag.write,
    );

    try payload.append(.{
        .tag = @intFromEnum(handover.Tags.STACK),
        .start = @intFromPtr(stack.ptr),
        .size = stack.len,
    });

    std.log.debug("Jump to ip: {x}, cr3: {x}", .{ hdr.entry, @intFromPtr(paging.root_page.root) });

    for (try loader.mmapSnapshot()) |mmap| {
        const tag: handover.Tags = switch (mmap.type) {
            .loader_code,
            .loader_data,
            .boot_services_code,
            .boot_services_data,
            .runtime_services_code,
            .runtime_services_data,
            => .LOADER,
            .conventional_memory => .FREE,
            else => .RESERVED,
        };

        const entry = handover.Record{
            .tag = @intFromEnum(tag),
            .start = mmap.physical_start,
            .size = mmap.number_of_pages * std.heap.pageSize(),
        };

        _ = entry;

        // try payload.append(entry);
    }

    try payload.append(.{
        .tag = @intFromEnum(handover.Tags.END),
        .start = std.math.maxInt(usize),
        .size = 0,
    });

    const ptr: usize = payload.finalize("booboot", handover.UPPER_HALF);
    try loader.deinit();

    asm volatile (
        \\ cli
        \\ mov %[stack], %%rsp
        \\ mov $0, %%rbp
        \\ mov %[page], %%cr3
        \\ call *%[entry]
        :
        : [page] "r" (@intFromPtr(paging.root_page.root)),
          [entry] "r" (hdr.entry),
          [stack] "r" (@intFromPtr(stack.ptr) + stack.len + handover.UPPER_HALF),
          [payload] "{rsi}" (ptr),
          [magic] "{rdi}" (@intFromEnum(handover.Tags.MAGIC)),
        : "cr3", "memory"
    );
}
