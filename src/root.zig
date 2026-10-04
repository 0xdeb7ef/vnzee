const std = @import("std");

const libvnc = @import("libvnc");
pub const rfbClient = libvnc.rfbClient;

pub const Client = struct {
    client: *rfbClient,

    const Bool = enum(@TypeOf(libvnc.TRUE)) {
        true = libvnc.TRUE,
        false = libvnc.FALSE,

        pub fn toBool(self: Bool) bool {
            return switch (self) {
                .true => true,
                .false => false,
            };
        }
    };

    pub fn getClient(
        bits_per_sample: c_int,
        samples_per_pixel: c_int,
        bytes_per_pixel: c_int,
    ) Client {
        return .{
            .client = libvnc.rfbGetClient(bits_per_sample, samples_per_pixel, bytes_per_pixel),
        };
    }

    pub fn init(client: *rfbClient) Client {
        return .{ .client = client };
    }

    pub fn initClient(self: Client, args: *const std.process.Args) bool {
        const c: *c_int = @ptrCast(@constCast(&args.vector.len));
        const v: [*]?[*]u8 = @ptrCast(@constCast(args.vector.ptr));

        const r: Bool = @fromBackingInt(@intCast(self.client.rfbInitClient(c, v)));
        return r.toBool();
    }

    pub fn cleanupClient(self: Client) void {
        self.client.rfbClientCleanup();
    }

    pub fn waitForMessage(self: Client, usecs: c_uint) c_int {
        return self.client.WaitForMessage(usecs);
    }

    pub fn handleRFBServerMessage(self: Client) bool {
        const r: Bool = @fromBackingInt(@intCast(self.client.HandleRFBServerMessage()));
        return r.toBool();
    }

    pub fn setClientData(self: Client, tag: anytype, data: anytype) void {
        self.client.rfbClientSetClientData(@ptrCast(@constCast(tag)), @ptrCast(@constCast(data)));
    }

    pub fn getClientData(self: Client, tag: anytype, T: type) *T {
        return @ptrCast(@alignCast(self.client.rfbClientGetClientData(@ptrCast(@constCast(tag)))));
    }

    const ButtonMask = struct {
        button1: bool = false,
        button2: bool = false,
        button3: bool = false,
        button4: bool = false,
        button5: bool = false,

        pub fn toMask(mask: ButtonMask) c_int {
            var m: c_int = 0;

            if (mask.button1) m |= libvnc.rfbButton1Mask;
            if (mask.button2) m |= libvnc.rfbButton2Mask;
            if (mask.button3) m |= libvnc.rfbButton3Mask;
            if (mask.button4) m |= libvnc.rfbButton4Mask;
            if (mask.button5) m |= libvnc.rfbButton5Mask;

            return m;
        }
    };

    pub fn sendPointerEvent(self: Client, x: c_int, y: c_int, button_mask: ButtonMask) bool {
        const r: Bool = @fromBackingInt(@intCast(self.client.SendPointerEvent(x, y, button_mask.toMask())));
        return r.toBool();
    }
};
