const std = @import("std");

fn runDemo(b: *std.Build, loader: *std.Build.Step.Compile) !void {
    const runStep = b.step("run", "Run the project");
    const buildStep = b.addInstallArtifact(loader, .{});
    const configCopy = b.addInstallFile(b.path("sample/loader.json"), "./sysroot/loader.json");
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

    efiCopy.step.dependOn(&buildStep.step);
    fetchBios.step.dependOn(&efiCopy.step);
    qemuStep.step.dependOn(&fetchBios.step);
    qemuStep.step.dependOn(&configCopy.step);
    runStep.dependOn(&qemuStep.step);
}

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
            .root_source_file = b.path("./src/loader/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });

    try runDemo(b, loader);
    b.installArtifact(loader);
}
