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

Run the following on your tablet:

```
vellum add vnzee
```

It's that simple!

You can also use [reManager](https://remanager.io).-->

## Source Install

### Prerequisites

- [reMarkable SDK](https://developer.remarkable.com/links) version 5.8.203
- [Zig](https://ziglang.org) version 0.17.0+

### Building

Run zig build to get builds for all devices:

```
zig build -Doptimize=ReleaseFast
```

You may also build for a specific device:

```
zig build -Doptimize=ReleaseFast -Ddevice=rmpp
```

### Installing

`zig-out` will contain the folder for each device, copy that into `~/xovi/exthome/appload/vnzee`
