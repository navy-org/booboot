const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = std.Target.Cpu.Arch.x86_64,
        .os_tag = std.Target.Os.Tag.uefi,
        .abi = std.Target.Abi.msvc,
    });
    const optimize = b.standardOptimizeOption(.{});
    const loader = b.addExecutable(.{
        .name = "booboot",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/loader/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });

    b.installArtifact(loader);

    const runStep = b.step("run", "Run the project");
    const buildStep = b.addInstallArtifact(loader, .{});
    const efiCopy = b.addInstallFile(loader.getEmittedBin(), "./sysroot/efi/boot/bootx64.efi");
    const fetchBios = b.addSystemCommand(&.{ "curl", "-C", "-", "https://retrage.github.io/edk2-nightly/bin/RELEASEX64_OVMF.fd", "-o", "./zig-out/bios.fd" });
    const qemuStep = b.addSystemCommand(&.{
        "qemu-system-x86_64",
        "-no-reboot",
        "-no-shutdown",
        "-display",
        "none",
        "-serial",
        "mon:stdio",
        "-drive",
        "format=raw,file=fat:rw:./zig-out/sysroot,media=disk",
        "-bios",
        "./zig-out/bios.fd",
    });

    runStep.dependOn(&buildStep.step);
    runStep.dependOn(&efiCopy.step);
    runStep.dependOn(&fetchBios.step);
    runStep.dependOn(&qemuStep.step);
}
