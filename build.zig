const std = @import("std");
const ResolvedTarget = std.Build.ResolvedTarget;
const LazyPath = std.Build.LazyPath;
const Compile = std.Build.Step.Compile;
const OptimizeMode = std.builtin.OptimizeMode;

const Target = struct {
    target: ResolvedTarget,
    include_dir: LazyPath,
    lib_dir: LazyPath,
    vendor: LazyPath,
    name: []const u8,
};

fn aarch64_target(b: *std.Build) Target {
    var cpu_features: std.Target.Cpu.Feature.Set = std.Target.aarch64.cpu.generic.features;
    cpu_features.addFeature(@intFromEnum(std.Target.aarch64.Feature.aes));
    cpu_features.addFeature(@intFromEnum(std.Target.aarch64.Feature.crc));
    cpu_features.addFeature(@intFromEnum(std.Target.aarch64.Feature.fp_armv8));
    cpu_features.addFeature(@intFromEnum(std.Target.aarch64.Feature.neon));
    cpu_features.addFeature(@intFromEnum(std.Target.aarch64.Feature.sha2));

    const t = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        // .cpu_model = .{ .explicit = &std.Target.aarch64.cpu.cortex_a53 },
        .cpu_features_add = cpu_features,
        .os_tag = .linux,
        .abi = .gnu,
        .glibc_version = .{
            .major = 2,
            .minor = 39,
            .patch = 0,
        },
    });

    return Target{
        .target = t,
        .include_dir = .{
            .cwd_relative = "/opt/codex/ferrari/5.5.125/sysroots/cortexa53-crypto-remarkable-linux/usr/include",
        },
        .lib_dir = .{
            .cwd_relative = "/opt/codex/ferrari/5.5.125/sysroots/cortexa53-crypto-remarkable-linux/usr/lib",
        },
        .vendor = b.path("vendor/aarch64"),
        .name = "aarch64",
    };
}

fn arm32_target(b: *std.Build) Target {
    var cpu_features: std.Target.Cpu.Feature.Set = std.Target.arm.cpu.generic.features;
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.aclass));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.d32));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.db));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.dsp));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.fp16));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.fp64));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.fpregs));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.fpregs64));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.has_v4t));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.has_v5t));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.has_v5te));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.has_v6));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.has_v6k));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.has_v6m));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.has_v6t2));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.has_v7));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.has_v7clrex));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.has_v8m));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.mp));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.neon));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.perfmon));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.ret_addr_stack));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.thumb2));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.trustzone));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.v7a));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.vfp2));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.vfp2sp));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.vfp3));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.vfp3d16));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.vfp3d16sp));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.vfp3sp));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.vmlx_forwarding));
    cpu_features.addFeature(@intFromEnum(std.Target.arm.Feature.vmlx_hazards));

    const t = b.resolveTargetQuery(.{
        .cpu_arch = .arm,
        // .cpu_model = .{ .explicit = &std.Target.aarch64.cpu.cortex_a53 },
        .cpu_features_add = cpu_features,
        .os_tag = .linux,
        .abi = .gnueabihf,
        .glibc_version = .{
            .major = 2,
            .minor = 39,
            .patch = 0,
        },
    });

    return Target{
        .target = t,
        .include_dir = .{
            .cwd_relative = "/opt/codex/rm1/5.5.125/sysroots/cortexa9hf-neon-remarkable-linux-gnueabi/usr/include",
        },
        .lib_dir = .{
            .cwd_relative = "/opt/codex/rm1/5.5.125/sysroots/cortexa9hf-neon-remarkable-linux-gnueabi/usr/lib",
        },
        .vendor = b.path("vendor/arm32"),
        .name = "arm32",
    };
}

pub fn create_artifact(b: *std.Build, t: Target, optimize: OptimizeMode) *Compile {
    const target = t.target;

    const rfbclient = t.vendor.path(b, "include/rfb/rfbclient.h");
    const rfbclient_c = b.addTranslateC(.{
        .root_source_file = rfbclient,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    rfbclient_c.addSystemIncludePath(t.vendor.path(b, "include"));
    rfbclient_c.addSystemIncludePath(t.include_dir);

    const libvnc_mod = rfbclient_c.createModule();
    libvnc_mod.addLibraryPath(t.lib_dir);
    libvnc_mod.addSystemIncludePath(t.include_dir);
    libvnc_mod.linkSystemLibrary("openssl", .{});
    libvnc_mod.linkSystemLibrary("gcrypt", .{});
    libvnc_mod.linkSystemLibrary("zlib", .{});
    libvnc_mod.linkSystemLibrary("jpeg", .{});

    const vnzee = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "libvnc", .module = libvnc_mod },
        },
    });

    vnzee.addObjectFile(t.vendor.path(b, "lib/libvncclient.a"));

    const zqtfb = b.dependency("zqtfb", .{}).module("zqtfb");

    const exe = b.addExecutable(.{
        .name = "vnzee",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "vnzee", .module = vnzee },
                .{ .name = "zqtfb", .module = zqtfb },
            },
        }),
    });
    return exe;
}

pub fn build(b: *std.Build) void {
    const targets = [_]Target{ aarch64_target(b), arm32_target(b) };
    const optimize = b.standardOptimizeOption(.{});

    for (targets) |target| {
        const c = create_artifact(b, target, optimize);
        const exe = b.addInstallArtifact(c, .{
            .dest_dir = .{
                .override = .{
                    .custom = target.name,
                },
            },
        });

        const manifest = b.addInstallFileWithDir(
            b.path("assets/manifest.json"),
            .{ .custom = target.name },
            "external.manifest.json",
        );

        // const icon = b.addInstallFileWithDir(
        //     b.path("assets/icon.png"),
        //     .{ .custom = target.name },
        //     "icon.png",
        // );

        b.getInstallStep().dependOn(&exe.step);
        b.getInstallStep().dependOn(&manifest.step);
        // b.getInstallStep().dependOn(&icon.step);
    }
}
