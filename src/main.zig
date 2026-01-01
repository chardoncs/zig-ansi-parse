const std = @import("std");

const root = @import("./root.zig");

const parseComptime = root.parseComptime;

pub fn main() !void {
    const demo_text = comptime parseComptime(
        \\<CYAN>Greetings!</> I'm <B>bold</B> and <BLUE;B>blue</>
        \\<NYAN>Ignore this</>
        \\\<escaped>
        \\<!TAB>tabbed<!LF>Ollal<!CR>Hello
        \\<!TAB*3>Three tabs
        \\
    , .{});

    std.debug.print(demo_text, .{});
}
