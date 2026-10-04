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
    input_id: ?i32 = null,
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

    const fb_type = detectFramebuffer(ctx.io) catch |err| {
        log.err("Unable to detect device type: {}", .{err});
        std.process.exit(1);
    };

    log.info("device type: {}, framebuffer: {}", .{ fb_type.getDevice(), fb_type });

    const fb = zqtfb.getIDFromAppLoad(init.minimal.environ) catch |err| {
        log.err("Unable to grab QTFB_KEY: {}", .{err});
        std.process.exit(1);
    };

    log.info("QTFB_KEY: /qtfb_{d}", .{fb});

    // matches rgb565 format
    const vnc: vnzee.Client = .getClient(0, 0, 0);
    // vnc_client.appData.encodingsString = "copyrect tight zrle hextile raw";
    vnc.client.format.bitsPerPixel = 16;
    vnc.client.format.depth = 16;
    vnc.client.format.redShift = 11;
    vnc.client.format.redMax = (1 << 5) - 1;
    vnc.client.format.greenShift = 5;
    vnc.client.format.greenMax = (1 << 6) - 1;
    vnc.client.format.blueShift = 0;
    vnc.client.format.blueMax = (1 << 5) - 1;

    // client data
    vnc.setClientData(&Tag.ctx, &ctx);

    // callbacks
    vnc.client.GotFrameBufferUpdate = update;
    vnc.client.FinishedFrameBufferUpdate = finishUpdate;
    vnc.client.GetPassword = struct {
        pub fn getPassword(client: ?*vnzee.rfbClient) callconv(.c) ?[*]u8 {
            const v: vnzee.Client = .init(client.?);
            const c: *Context = v.getClientData(&Tag.ctx, Context);

            const password = c.env.getPosix("VNZEE_PASSWORD") orelse "";
            const pw = std.heap.c_allocator.dupeSentinel(u8, password, 0) catch {
                @panic("cannot allocate memory for a password, seriously?");
            };
            return @ptrCast(pw);
        }
    }.getPassword;

    // init libvnc
    const r = vnc.initClient(&init.minimal.args);
    defer if (r) vnc.cleanupClient();
    if (!r) std.process.exit(1);

    // init zqtfb
    ctx.zclient = zqtfb.Client.init(ctx.io, fb, fb_type, .{
        .width = @intCast(vnc.client.width),
        .height = @intCast(vnc.client.height),
    }, true) catch |err| {
        log.err("Unable to create QTFB client: {}", .{err});
        std.process.exit(1);
    };
    defer ctx.zclient.deinit(ctx.io);

    // map libvnc's framebuffer to zqtfb's display
    vnc.client.frameBuffer = ctx.zclient.display.ptr;

    ctx.zclient.setRefreshMode(ctx.io, .animate) catch unreachable;
    ctx.zclient.fullUpdate(ctx.io) catch unreachable;

    var poll_fds: [2]std.posix.pollfd = .{
        .{
            .fd = vnc.client.sock,
            .events = std.posix.POLL.IN,
            .revents = 0,
        },
        .{
            .fd = ctx.zclient.socket.socket.handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        },
    };

    // event loop
    while (true) event_loop: {
        _ = try std.posix.poll(&poll_fds, if (vnc.client.buffered != 0) 0 else -1);
        const POLL_ERR = std.posix.POLL.ERR | std.posix.POLL.HUP | std.posix.POLL.NVAL;

        for (poll_fds) |poll_fd| {
            if (poll_fd.revents & POLL_ERR != 0) {
                break :event_loop;
            }
        }

        if (poll_fds[1].revents & std.posix.POLL.IN != 0) {
            const packet = try ctx.zclient.pollServerPacket(ctx.io);
            if (packet.type == .user_input) {
                handleInput(vnc, packet);
            }
        }

        if (vnc.client.buffered != 0 or poll_fds[0].revents & std.posix.POLL.IN != 0) {
            if (!vnc.handleRFBServerMessage()) break;
        }
    }
}

fn handleInput(client: vnzee.Client, packet: zqtfb.Message.ServerMessage) void {
    const ctx: *Context = client.getClientData(&Tag.ctx, Context);

    switch (packet.message.input.type) {
        .pen_press => {
            if (ctx.input_id == null) {
                ctx.input_id = packet.message.input.device_id;
                const x = packet.message.input.x;
                const y = packet.message.input.y;

                _ = client.sendPointerEvent(x, y, .{ .button1 = true });
            }
        },
        .pen_update => {
            if (ctx.input_id == packet.message.input.device_id) {
                const x = packet.message.input.x;
                const y = packet.message.input.y;

                _ = client.sendPointerEvent(x, y, .{ .button1 = true });
            }
        },
        .pen_release => {
            if (ctx.input_id == packet.message.input.device_id) {
                const x = packet.message.input.x;
                const y = packet.message.input.y;

                _ = client.sendPointerEvent(x, y, .{ .button1 = false });
            }
        },
        .touch_release => {
            if (ctx.zclient.refresh_mode == .animate) {
                ctx.zclient.setRefreshMode(ctx.io, .ufast) catch |err| {
                    log.err("Unable to update refresh mode: {}", .{err});
                };
            } else {
                ctx.zclient.setRefreshMode(ctx.io, .animate) catch |err| {
                    log.err("Unable to update refresh mode: {}", .{err});
                };
            }
        },
        else => {
            return;
        },
    }
}

fn update(client: ?*vnzee.rfbClient, x: c_int, y: c_int, w: c_int, h: c_int) callconv(.c) void {
    const vnc: vnzee.Client = .init(client.?);
    const ctx: *Context = vnc.getClientData(&Tag.ctx, Context);

    const rect = Rect{
        .left = x,
        .top = y,
        .right = x + w,
        .bottom = y + h,
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

fn finishUpdate(client: ?*vnzee.rfbClient) callconv(.c) void {
    const vnc: vnzee.Client = .init(client.?);
    const ctx: *Context = vnc.getClientData(&Tag.ctx, Context);
    const rect = ctx.dirty orelse return;

    ctx.zclient.partialUpdate(
        ctx.io,
        rect.left,
        rect.top,
        rect.right - rect.left,
        rect.bottom - rect.top,
    ) catch |err| {
        log.err("Error updating screen: {}", .{err});
        return;
    };
    ctx.dirty = null;
}

fn detectFramebuffer(io: Io) !zqtfb.Message.FramebufferType {
    const device = try zqtfb.Device.getDevice(io);

    return switch (device) {
        .rM2 => .rM2_fb,
        .rMPP => .rMPP_rgb565,
        .rMPPM => .rMPPM_rgb565,
        .rMPPure => .rMPPure_rgb565,
    };
}
