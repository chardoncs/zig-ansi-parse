# zig-ansi-parse

Comptime-proof ANSI format parsing library for Zig.

[How it works?](https://github.com/chardoncs/zig-ansi-parse/wiki/Syntax)

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
