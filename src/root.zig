const cp = @import("./parse-comptime.zig");

pub const parseComptime = cp.parseComptime;
pub const ComptimeParserOptions = cp.ParserOptions;

test {
    // Pull the parser's test blocks into this module's test build.
    _ = @import("./parse-comptime.zig");
}
