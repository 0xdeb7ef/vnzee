const std = @import("std");
const ResolvedTarget = std.Build.ResolvedTarget;
const LazyPath = std.Build.LazyPath;
const Compile = std.Build.Step.Compile;
const OptimizeMode = std.builtin.OptimizeMode;

const remarkable = @import("zig_remarkable");

const Target = struct {
    target: ResolvedTarget,
    include_dir: LazyPath,
    lib_dir: LazyPath,
    vendor: LazyPath,
    name: []const u8,
};

fn rmpp_target(b: *std.Build) Target {
    return Target{
        .target = remarkable.resolve(b, .ferrari),
        .include_dir = .{
            .cwd_relative = "/opt/codex/ferrari/5.8.203/sysroots/cortexa53-crypto-remarkable-linux/usr/include",
        },
        .lib_dir = .{
            .cwd_relative = "/opt/codex/ferrari/5.8.203/sysroots/cortexa53-crypto-remarkable-linux/usr/lib",
        },
        .vendor = b.path("vendor/rmpp"),
        .name = "rmpp",
    };
}

fn rm2_target(b: *std.Build) Target {
    return Target{
        .target = remarkable.resolve(b, .rm2),
        .include_dir = .{
            .cwd_relative = "/opt/codex/rm2/5.8.203/sysroots/cortexa7hf-neon-remarkable-linux-gnueabi/usr/include",
        },
        .lib_dir = .{
            .cwd_relative = "/opt/codex/rm2/5.8.203/sysroots/cortexa7hf-neon-remarkable-linux-gnueabi/usr/lib",
        },
        .vendor = b.path("vendor/rm2"),
        .name = "rm2",
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
        .strip = switch (optimize) {
            .Debug => false,
            .ReleaseFast, .ReleaseSafe, .ReleaseSmall => true,
        },
        .imports = &.{
            .{ .name = "libvnc", .module = libvnc_mod },
        },
    });

    vnzee.addObjectFile(t.vendor.path(b, "lib/libvncclient.a"));

    const zqtfb = b.dependency("zqtfb", .{ .target = target }).module("zqtfb");

    const exe = b.addExecutable(.{
        .name = "vnzee",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = switch (optimize) {
                .Debug => false,
                .ReleaseFast, .ReleaseSafe, .ReleaseSmall => true,
            },
            .imports = &.{
                .{ .name = "vnzee", .module = vnzee },
                .{ .name = "zqtfb", .module = zqtfb },
            },
        }),
    });
    return exe;
}

pub fn build(b: *std.Build) void {
    const targets = [_]Target{ rmpp_target(b), rm2_target(b) };
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
