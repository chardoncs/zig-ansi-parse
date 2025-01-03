const std = @import("std");

const root = @import("./root.zig");

const parseComptime = root.parseComptime;

const demo_text = parseComptime(
    \\<CYAN>Greetings!</> I'm <B>bold</B> and <BLUE;B>blue</>
    \\<NYAN>Ignore this</>
    \\\<escaped>
    \\<!TAB>tabbed<!LF>Ollal<!CR>Hello
    \\<!TAB*3>Three tabs
    \\
, .{});

pub fn main() !void {
    std.debug.print(demo_text, .{});
}
