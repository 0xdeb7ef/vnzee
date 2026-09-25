# VNZee

A minimal VNC client for reMarkable devices. Uses [libvnc](https://github.com/LibVNC/libvncserver) and [zqtfb](https://github.com/0xdeb7ef/zqtfb) under the hood.

## Functionality

- Can connect to VNC servers.
- Uses the resolution sent by the VNC server.
- Works in both landscape and portrait.
- Supports input via the **pen only** (there is a bug in [AppLoad](https://github.com/asivery/rm-appload) preventing touch input from working properly).
- Switch between `animate` and `ufast` modes by tapping the screen.

## Usage

Edit `~/xovi/exthome/appload/vnzee/external.manifest.json` to your liking, then launch it from within AppLoad.

You can also pass an `-encodings` parameter in order to control which encodings the client will use:

```json
"args": [
  "-encodings", "copyrect tight zrle hextile raw",
  "127.0.0.1:5900"
],
```

<!--## Vellum Install

```
vellum add vnzee
```-->

## Source Install

### Prerequisites

- [reMarkable SDK](https://developer.remarkable.com/links) version 5.8.203
- [Zig](https://ziglang.org) version 0.16.0+

### Building

Run zig build to get builds for the reMarkable 2 and reMarkable Paper Pro:

```
zig build -Doptimize=ReleaseFast
```

### Installing

Copy whatever is in `zig-out/rmpp` or `zig-out/rm2` to `~/xovi/exthome/appload/vnzee` on your tablet.
