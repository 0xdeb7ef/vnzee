const std = @import("std");
const Io = std.Io;
const Clock = Io.Clock;
const Environ = std.process.Environ;

const vnzee = @import("vnzee");
const zqtfb = @import("zqtfb");

const log = std.log.scoped(.vnzee);

var last_update: std.Io.Timestamp = .zero;
var buffer: []u8 = undefined;

const Context = struct {
    io: Io,
    clock: Clock,
    env: Environ,
    zclient: zqtfb.Client,
};

const Tag = enum {
    ctx,
};

pub fn main(init: std.process.Init) !void {
    var ctx = Context{
        .io = init.io,
        .clock = .real,
        .zclient = undefined,
        .env = init.minimal.environ,
    };

    const device = detect_device(ctx.io);

    log.info("device type: {}", .{device});

    const fb = zqtfb.getIDFromAppLoad(init.minimal.environ) catch |err| {
        log.err("Unable to grab QTFB_KEY: {}", .{err});
        std.process.exit(1);
    };

    // matches rgb565 format
    const vnc_client = vnzee.getClient(0, 0, 0);
    vnc_client.appData.encodingsString = "copyrect";
    vnc_client.format.bitsPerPixel = 16;
    vnc_client.format.depth = 16;
    vnc_client.format.redShift = 11;
    vnc_client.format.redMax = (1 << 5) - 1;
    vnc_client.format.greenShift = 5;
    vnc_client.format.greenMax = (1 << 6) - 1;
    vnc_client.format.blueShift = 0;
    vnc_client.format.blueMax = (1 << 5) - 1;

    // client data
    vnzee.setClientData(vnc_client, &Tag.ctx, &ctx);

    // callbacks
    vnc_client.GotFrameBufferUpdate = update;
    vnc_client.GetPassword = struct {
        pub fn getPassword(client: ?*vnzee.Client) callconv(.c) ?[*]u8 {
            const c: *Context = vnzee.getClientData(client.?, &Tag.ctx, Context);

            const password = c.env.getPosix("VNZEE_PASSWORD") orelse "";
            const pw = std.heap.c_allocator.dupeSentinel(u8, password, 0) catch {
                @panic("cannot allocate memory for a password, seriously?");
            };
            return @ptrCast(pw);
        }
    }.getPassword;

    // init libvnc
    const r = vnzee.initClient(vnc_client, &init.minimal.args);
    defer if (r) vnzee.cleanupClient(vnc_client);
    if (!r) std.process.exit(1);

    // init zqtfb
    ctx.zclient = zqtfb.Client.init(ctx.io, fb, device, .{
        .width = @intCast(@min(vnc_client.width, vnc_client.height)),
        .height = @intCast(@max(vnc_client.width, vnc_client.height)),
    }, true) catch |err| {
        log.err("Unable to create qtfb client: {}", .{err});
        std.process.exit(1);
    };
    defer ctx.zclient.deinit(ctx.io);

    // create a buffer
    buffer = try init.gpa.alloc(u8, @as(usize, ctx.zclient.width) * @as(usize, ctx.zclient.height) * ctx.zclient.getBPS());
    defer init.gpa.free(buffer);

    ctx.zclient.setRefreshMode(ctx.io, .animate) catch unreachable;
    ctx.zclient.fullUpdate(ctx.io) catch unreachable;

    var poll_fds: [1]std.posix.pollfd = .{.{
        .fd = vnc_client.sock,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};

    // event loop
    while (true) {
        _ = std.posix.poll(&poll_fds, 1) catch unreachable;
        if (poll_fds[0].revents & std.posix.POLL.IN != 0) {
            if (!vnzee.handleRFBServerMessage(vnc_client)) break;
        }

        // const n = vnzee.waitForMessage(vnc_client, 1);
        // if (n < 0) break;
        // if (n > 0) if (!vnzee.handleRFBServerMessage(vnc_client)) break;

        // check if no activity has happened in the last 3 seconds,
        // set to content mode if so
        if (last_update.untilNow(ctx.io, ctx.clock).toSeconds() > 3 and ctx.zclient.refresh_mode != .content) {
            ctx.zclient.setRefreshMode(ctx.io, .content) catch unreachable;
            ctx.zclient.fullUpdate(ctx.io) catch unreachable;
        }
    }

    std.process.exit(0);
}

fn update(client: ?*vnzee.Client, x: c_int, y: c_int, w: c_int, h: c_int) callconv(.c) void {
    const ctx: *Context = vnzee.getClientData(client.?, &Tag.ctx, Context);

    // reset to animate mode for faster refresh
    const now = ctx.clock.now(ctx.io);
    if (ctx.zclient.refresh_mode != .animate and
        last_update.untilNow(ctx.io, ctx.clock).toSeconds() <= 3)
    {
        ctx.zclient.setRefreshMode(ctx.io, .animate) catch unreachable;
    }

    // rotate screen 90 degrees if it's landscape
    const width: usize = @intCast(client.?.width);
    const height: usize = @intCast(client.?.height);
    if (width > height) {
        for (0..height) |hh| {
            for (0..width) |ww| {
                const bps = ctx.zclient.getBPS();
                const i = ctx.zclient.getPixel(@intCast(height - 1 - hh), @intCast(ww));
                const ii = (hh * width + ww) * bps;
                @memcpy(ctx.zclient.display[i .. i + bps], client.?.frameBuffer[ii .. ii + bps]);
            }
        }
        // @memcpy(ctx.zclient.display, client.?.frameBuffer);
    } else {
        @memcpy(ctx.zclient.display, client.?.frameBuffer);
        // @memcpy(buffer, client.?.frameBuffer);
        // @memcpy(c.zclient.display, buffer);
    }

    // now = ctx.clock.now(ctx.io);
    if (last_update.durationTo(now).toMilliseconds() > 50) {
        ctx.zclient.partialUpdate(ctx.io, x, y, w, h) catch |err| {
            log.err("Error updating screen: {}", .{err});
        };
        last_update = now;
    }
}

fn detect_device(io: Io) zqtfb.Message.FramebufferType {
    const device_file = std.Io.Dir.cwd().openFile(io, "/sys/devices/soc0/machine", .{}) catch {
        @panic("could not open /sys/devices/soc0/machine. Are you on a reMarkable device?");
    };
    defer device_file.close(io);

    var buf: [64]u8 = undefined;

    _ = device_file.readPositionalAll(io, &buf, 0) catch unreachable;

    if (std.mem.containsAtLeast(u8, &buf, 1, "Chiappa")) {
        return zqtfb.Message.FramebufferType.rMPPM_rgb565;
    } else if (std.mem.containsAtLeast(u8, &buf, 1, "Ferrari")) {
        return zqtfb.Message.FramebufferType.rMPP_rgb565;
    } else if (std.mem.containsAtLeast(u8, &buf, 1, "2.0")) {
        return zqtfb.Message.FramebufferType.rM2_fb;
    } else {
        return zqtfb.Message.FramebufferType.rM2_fb; // rM1 has same res as rM2
    }
}
