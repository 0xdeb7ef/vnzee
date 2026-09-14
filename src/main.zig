const std = @import("std");
const Io = std.Io;
const Environ = std.process.Environ;

const vnzee = @import("vnzee");
const zqtfb = @import("zqtfb");

const log = std.log.scoped(.vnzee);

const Rect = struct {
    left: c_int,
    top: c_int,
    right: c_int,
    bottom: c_int,
};

const Context = struct {
    io: Io,
    env: Environ,
    zclient: zqtfb.Client,
    dirty: ?Rect = null,
};

const Tag = enum {
    ctx,
};

pub fn main(init: std.process.Init) !void {
    var ctx = Context{
        .io = init.io,
        .zclient = undefined,
        .env = init.minimal.environ,
    };

    const device = detectDevice(ctx.io);

    log.info("device type: {}", .{device});

    const fb = zqtfb.getIDFromAppLoad(init.minimal.environ) catch |err| {
        log.err("Unable to grab QTFB_KEY: {}", .{err});
        std.process.exit(1);
    };

    // matches rgb565 format
    const vnc_client = vnzee.getClient(0, 0, 0);
    // vnc_client.appData.encodingsString = "copyrect tight zrle hextile raw";
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
    vnc_client.FinishedFrameBufferUpdate = finishUpdate;
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

    ctx.zclient.setRefreshMode(ctx.io, .animate) catch unreachable;
    ctx.zclient.fullUpdate(ctx.io) catch unreachable;

    var poll_fds: [1]std.posix.pollfd = .{.{
        .fd = vnc_client.sock,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};

    // event loop
    while (true) {
        _ = try std.posix.poll(&poll_fds, if (vnc_client.buffered != 0) 0 else -1);
        if (vnc_client.buffered != 0 or poll_fds[0].revents & std.posix.POLL.IN != 0) {
            if (!vnzee.handleRFBServerMessage(vnc_client)) break;
        } else if (poll_fds[0].revents & (std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL) != 0) {
            break;
        }
    }
}

fn update(client: ?*vnzee.Client, x: c_int, y: c_int, w: c_int, h: c_int) callconv(.c) void {
    const vnc_client = client.?;
    const ctx: *Context = vnzee.getClientData(vnc_client, &Tag.ctx, Context);

    const width: usize = @intCast(vnc_client.width);
    const height: usize = @intCast(vnc_client.height);
    const left: usize = @intCast(x);
    const top: usize = @intCast(y);
    const right: usize = @intCast(x + w);
    const bottom: usize = @intCast(y + h);
    // const bps = ctx.zclient.getBPS();
    const bps: usize = 2;
    const rotate = width > height;

    // rotate the pixels and refresh bounds 90 degrees if the source is landscape
    // this is slow, maybe there's a way to improve it?
    if (rotate) {
        for (top..bottom) |row| {
            for (left..right) |col| {
                const dst = (col * height + height - 1 - row) * bps;
                const src = (row * width + col) * bps;
                @memcpy(ctx.zclient.display[dst .. dst + bps], vnc_client.frameBuffer[src .. src + bps]);
            }
        }
    } else {
        // this is also probably not optimal
        for (top..bottom) |row| {
            const start = (row * width + left) * bps;
            const end = (row * width + right) * bps;
            @memcpy(ctx.zclient.display[start..end], vnc_client.frameBuffer[start..end]);
        }
    }

    const rect = Rect{
        .left = if (rotate) vnc_client.height - y - h else x,
        .top = if (rotate) x else y,
        .right = if (rotate) vnc_client.height - y else x + w,
        .bottom = if (rotate) x + w else y + h,
    };

    if (ctx.dirty) |*dirty| {
        dirty.left = @min(dirty.left, rect.left);
        dirty.top = @min(dirty.top, rect.top);
        dirty.right = @max(dirty.right, rect.right);
        dirty.bottom = @max(dirty.bottom, rect.bottom);
    } else {
        ctx.dirty = rect;
    }
}

fn finishUpdate(client: ?*vnzee.Client) callconv(.c) void {
    const ctx: *Context = vnzee.getClientData(client.?, &Tag.ctx, Context);
    const rect = ctx.dirty orelse return;
    ctx.zclient.partialUpdate(ctx.io, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top) catch |err| {
        log.err("Error updating screen: {}", .{err});
        return;
    };
    ctx.dirty = null;
}

fn detectDevice(io: Io) zqtfb.Message.FramebufferType {
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
