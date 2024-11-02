# zig-ansi-parse

Comptime-proof ANSI format parsing library for Zig.

[How it works?](https://github.com/chardoncs/zig-ansi-parse/wiki/Syntax)

## Install

1. Fetch it in your project, `<version>` is the version you want

```bash
zig fetch --save https://github.com/chardoncs/zig-ansi-parse/archive/refs/tags/v<version>.tar.gz
```

Or fetch the git repo for latest updates

```bash
zig fetch --save git+https://github.com/chardoncs/zig-ansi-parse
```

2. Configure your `build.zig`. Replace `<compile-var>` with the variable name of the compile target

```zig
const ansi_parse = b.dependency("ansi-parse", .{});
<compile-var>.root_module.addImport("ansi-parse", ansi_parse.module("ansi-parse"));
```

## At a glance

```zig
const std = @import("std");
const parseComptime = @import("ansi-parse").parseComptime;

const demo_text = parseComptime(
    \\<CYAN>Greetings!</> I'm <B>bold</> and <BLUE;B>blue</>
    \\<NYAN>Ignore this</>
    \\\<escaped>
    \\<!TAB>tabbed<!LF>Ollal<!CR>Hello
    \\<!TAB*3>Three tabs
    \\
);

pub fn main() !void {
    std.debug.print(demo_text, .{});
}
```
