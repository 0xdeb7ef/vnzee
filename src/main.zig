const std = @import("std");
const Environ = std.process.Environ;

const vnzee = @import("vnzee");
const zqtfb = @import("zqtfb");

const log = std.log.scoped(.vnzee);

var io: std.Io = undefined;
var zclient: zqtfb.Client = undefined;

var clock: std.Io.Clock = undefined;
var last_update: std.Io.Timestamp = .zero;

var environ: Environ = undefined;

var buffer: []u8 = undefined;

pub fn main(init: std.process.Init) !void {
    io = init.io;
    clock = .real;
    environ = init.minimal.environ;

    const fb = zqtfb.getIDFromAppLoad(init.minimal.environ) catch |err| {
        log.err("Unable to grab QTFB_KEY: {}", .{err});
        std.process.exit(1);
    };

    // matches rmpp_rgb565 format
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

    // callbacks
    vnc_client.GotFrameBufferUpdate = update;
    vnc_client.GetPassword = struct {
        pub fn getPassword(_: ?[*]vnzee.Client) callconv(.c) ?[*]u8 {
            const password = environ.getPosix("VNZEE_PASSWORD") orelse "";
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
    zclient = zqtfb.Client.init(io, fb, .rMPP_rgb565, .{
        .width = @intCast(@min(vnc_client.width, vnc_client.height)),
        .height = @intCast(@max(vnc_client.width, vnc_client.height)),
    }, true) catch |err| {
        log.err("Unable to create qtfb client: {}", .{err});
        std.process.exit(1);
    };
    defer zclient.deinit(io);

    // create a buffer
    buffer = try init.gpa.alloc(u8, @as(usize, zclient.width) * @as(usize, zclient.height) * zclient.getBPS());
    defer init.gpa.free(buffer);

    // event loop
    while (true) {
        const n = vnzee.waitForMessage(vnc_client, 500);
        if (n < 0) break;
        if (n > 0) if (!vnzee.handleRFBServerMessage(vnc_client)) break;

        // check if no activity has happened in the last 3 seconds,
        // set to content mode if so
        if (last_update.untilNow(io, clock).toSeconds() > 3 and zclient.refresh_mode != .content) {
            zclient.setRefreshMode(io, .content) catch unreachable;
            zclient.fullUpdate(io) catch unreachable;
        }
    }

    std.process.exit(0);
}

fn update(client: ?*vnzee.Client, x: c_int, y: c_int, w: c_int, h: c_int) callconv(.c) void {
    // reset to animate mode for faster refresh
    const now = clock.now(io);
    if (zclient.refresh_mode != .animate and last_update.untilNow(io, clock).toSeconds() <= 3) {
        zclient.setRefreshMode(io, .animate) catch unreachable;
    }

    // rotate screen 90 degrees if it's landscape
    const width: usize = @intCast(client.?.width);
    const height: usize = @intCast(client.?.height);
    if (width > height) {
        for (0..height) |hh| {
            for (0..width) |ww| {
                const i = zclient.getPixel(@intCast(height - 1 - hh), @intCast(ww));
                const ii = (hh * width + ww) * zclient.getBPS();
                @memcpy(buffer[i .. i + zclient.getBPS()], client.?.frameBuffer[ii .. ii + zclient.getBPS()]);
            }
        }
        @memcpy(zclient.display, buffer);
    } else {
        @memcpy(buffer, client.?.frameBuffer);
        @memcpy(zclient.display, buffer);
    }

    zclient.partialUpdate(io, x, y, w, h) catch |err| {
        log.err("Error updating screen: {}", .{err});
    };

    last_update = now;
}
