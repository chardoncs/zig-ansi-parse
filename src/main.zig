const std = @import("std");

const root = @import("./root.zig");

const ComptimeParser = root.ComptimeParser;

const demo_text = ComptimeParser(
    \\<CYAN>Hello!</> I'm <B>bold</> and <BLUE;B>blue</>
    \\
).parse();

pub fn main() !void {
    std.debug.print(demo_text, .{});
}
