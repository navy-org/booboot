const std = @import("std");

fn bareboneKernel(b: *std.Build, opti: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    var logo = b.addInstallFile(
        b.path("sample/assets/logo.tga"),
        "./sysroot/logo.tga",
    );

    var target: std.Target.Query = .{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    };

    const Features = std.Target.x86.Feature;
    target.cpu_features_sub.addFeature(@intFromEnum(Features.mmx));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.sse));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.sse2));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.avx));
    target.cpu_features_sub.addFeature(@intFromEnum(Features.avx2));
    target.cpu_features_add.addFeature(@intFromEnum(Features.soft_float));

    const exe = b.addExecutable(.{
        .name = "barebone",
        .optimize = opti,
        .code_model = .kernel,
        .target = b.resolveTargetQuery(target),
    });
    exe.addIncludePath(b.path("sample/src"));
    exe.addCSourceFiles(.{
        .root = b.path("sample/src"),
        .files = &.{
            "handover.c",
            "main.c",
            "stdlib.c",
            "stdio.c",
            "string.c",
        },
        .flags = &.{
            "-Wall",
            "-Werror",
            "-Wextra",
            "-std=gnu2y",
            "-fcolor-diagnostics",
        },
    });

    exe.step.dependOn(&logo.step);

    return exe;
}

fn runDemo(b: *std.Build, loader: *std.Build.Step.Compile) !void {
    const runStep = b.step("run", "Run the project");
    const buildStep = b.addInstallArtifact(loader, .{});
    const configCopy = b.addInstallFile(b.path("sample/loader.json"), "./sysroot/loader.json");
    const efiCopy = b.addInstallFile(loader.getEmittedBin(), "./sysroot/efi/boot/bootx64.efi");
    const fetchBios = b.addSystemCommand(&.{ "curl", "-C", "-", "https://retrage.github.io/edk2-nightly/bin/RELEASEX64_OVMF.fd", "-o", "./zig-out/bios.fd" });
    const kernel = bareboneKernel(b, loader.root_module.optimize.?);
    const kernelCopy = b.addInstallFile(kernel.getEmittedBin(), "./sysroot/kernel.elf");
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
    kernelCopy.step.dependOn(&kernel.step);
    qemuStep.step.dependOn(&kernelCopy.step);
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

    const arch = b.addModule("arch", .{
        .root_source_file = b.path("./src/loader/arch/x86_64/root.zig"),
    });

    const handover = b.addModule("handover", .{
        .root_source_file = b.path("./src/specs/handover/root.zig"),
    });

    arch.addImport("flags", b.addModule("flags", .{ .root_source_file = b.path("./src/loader/arch/flags.zig") }));
    arch.addImport("handover", handover);
    loader.root_module.addImport("handover", handover);
    loader.root_module.addImport("arch", arch);

    try runDemo(b, loader);
    b.installArtifact(loader);
}
