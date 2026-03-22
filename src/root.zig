const std = @import("std");

const libvnc = @import("libvnc");
pub const Client = libvnc.rfbClient;

pub const Bool = enum(i8) {
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
) *Client {
    return libvnc.rfbGetClient(bits_per_sample, samples_per_pixel, bytes_per_pixel);
}

pub fn initClient(client: *Client, args: *const std.process.Args) bool {
    const c: *c_int = @ptrCast(@constCast(&args.vector.len));
    const v: [*]?[*]u8 = @ptrCast(@constCast(args.vector.ptr));

    const r: Bool = @enumFromInt(libvnc.rfbInitClient(client, c, v));
    return r.toBool();
}

pub fn cleanupClient(client: *Client) void {
    libvnc.rfbClientCleanup(client);
}

pub fn waitForMessage(client: *Client, usecs: c_uint) c_int {
    return libvnc.WaitForMessage(client, usecs);
}

pub fn handleRFBServerMessage(client: *Client) bool {
    const r: Bool = @enumFromInt(libvnc.HandleRFBServerMessage(client));
    return r.toBool();
}
