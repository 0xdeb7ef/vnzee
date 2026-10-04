const std = @import("std");
const ResolvedTarget = std.Build.ResolvedTarget;
const LazyPath = std.Build.LazyPath;
const Compile = std.Build.Step.Compile;
const OptimizeMode = std.builtin.OptimizeMode;

const remarkable = @import("zqtfb").remarkable;
const Translator = @import("translate_c").Translator;

const Target = struct {
    target: ResolvedTarget,
    include_dir: LazyPath,
    lib_dir: LazyPath,
    vendor: LazyPath,
    name: []const u8,
};

const Manifest = .{
    .name = "VNZee",
    .application = "vnzee",
    .qtfb = true,
    .args = &.{ "127.0.0.1", "5900" },
    .environment = .{
        .VNZEE_PASSWORD = "password",
    },
};

fn rm1_target(b: *std.Build) Target {
    return Target{
        .target = remarkable.resolve(b, .rm1),
        .include_dir = .{
            .cwd_relative = "/opt/codex/rm1/5.8.203/sysroots/cortexa9hf-neon-remarkable-linux-gnueabi/usr/include",
        },
        .lib_dir = .{
            .cwd_relative = "/opt/codex/rm1/5.8.203/sysroots/cortexa9hf-neon-remarkable-linux-gnueabi/usr/lib",
        },
        .vendor = b.path("vendor/rm1"),
        .name = "rm1",
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

fn ferrari_target(b: *std.Build) Target {
    return Target{
        .target = remarkable.resolve(b, .ferrari),
        .include_dir = .{
            .cwd_relative = "/opt/codex/ferrari/5.8.203/sysroots/cortexa53-crypto-remarkable-linux/usr/include",
        },
        .lib_dir = .{
            .cwd_relative = "/opt/codex/ferrari/5.8.203/sysroots/cortexa53-crypto-remarkable-linux/usr/lib",
        },
        .vendor = b.path("vendor/ferrari"),
        .name = "ferrari",
    };
}

fn chiappa_target(b: *std.Build) Target {
    return Target{
        .target = remarkable.resolve(b, .chiappa),
        .include_dir = .{
            .cwd_relative = "/opt/codex/chiappa/5.8.203/sysroots/cortexa55-remarkable-linux/usr/include",
        },
        .lib_dir = .{
            .cwd_relative = "/opt/codex/chiappa/5.8.203/sysroots/cortexa55-remarkable-linux/usr/lib",
        },
        .vendor = b.path("vendor/chiappa"),
        .name = "chiappa",
    };
}

fn tatsu_target(b: *std.Build) Target {
    return Target{
        .target = remarkable.resolve(b, .tatsu),
        .include_dir = .{
            .cwd_relative = "/opt/codex/tatsu/5.8.203/sysroots/cortexa55-remarkable-linux/usr/include",
        },
        .lib_dir = .{
            .cwd_relative = "/opt/codex/tatsu/5.8.203/sysroots/cortexa55-remarkable-linux/usr/lib",
        },
        .vendor = b.path("vendor/tatsu"),
        .name = "tatsu",
    };
}

pub fn create_artifact(b: *std.Build, t: Target, optimize: OptimizeMode) *Compile {
    const target = t.target;
    const translate_c = b.dependency("translate_c", .{});

    const rfbclient: Translator = .init(translate_c, .{
        .c_source_file = t.vendor.path(b, "include/rfb/rfbclient.h"),
        .target = target,
        .optimize = optimize,
        .default_init = false,
    });

    rfbclient.addIncludePath(t.vendor.path(b, "include"));
    rfbclient.addSystemIncludePath(t.include_dir);

    const libvnc_mod = rfbclient.mod;
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

    const zqtfb = b.dependency("zqtfb", .{}).module("zqtfb");

    const exe = b.addExecutable(.{
        .name = Manifest.application,
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

const Targets = enum {
    rm1,
    rm2,
    rmpp,
    rmppm,
    rmppure,
    all,
};

pub fn build(b: *std.Build) void {
    const all_targets = [_]?Target{
        rm1_target(b),
        rm2_target(b),
        ferrari_target(b),
        chiappa_target(b),
        tatsu_target(b),
    };

    const device = b.option(Targets, "device", "reMarkable device to build for (default: all)") orelse .all;
    const optimize = b.standardOptimizeOption(.{});

    const targets: [5]?Target = switch (device) {
        .rm1 => [5]?Target{ all_targets[0], null, null, null, null },
        .rm2 => [5]?Target{ all_targets[1], null, null, null, null },
        .rmpp => [5]?Target{ all_targets[2], null, null, null, null },
        .rmppm => [5]?Target{ all_targets[3], null, null, null, null },
        .rmppure => [5]?Target{ all_targets[4], null, null, null, null },
        .all => all_targets,
    };

    for (targets) |t| {
        if (t) |target| {
            const c = create_artifact(b, target, optimize);
            const exe = b.addInstallArtifact(c, .{
                .dest_dir = .{
                    .override = .{
                        .custom = target.name,
                    },
                },
            });

            const json = std.fmt.allocPrint(
                b.allocator,
                "{f}\n",
                .{std.json.fmt(
                    Manifest,
                    .{ .whitespace = .indent_2 },
                )},
            ) catch unreachable;

            const manifest = b.addInstallFileWithDir(
                b.addWriteFiles().add("manifest", json),
                exe.dest_dir.?,
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
}
