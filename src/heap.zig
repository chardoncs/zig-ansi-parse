const std = @import("std");

const core = @import("./core.zig");

const Allocator = std.mem.Allocator;
const String = std.ArrayList(u8);

const ParserOptions = core.ParserOptions;
const genericParse = core.genericParse;

inline fn _true(_: *const String) bool {
    return true;
}

pub fn parse(allocator: Allocator, input: []const u8, comptime opt: anytype) Allocator.Error![:0]const u8 {
    const opt_struct = comptime ParserOptions.initComptime(opt);
    var buffer = String.initCapacity(allocator, opt_struct.out_size orelse (input.len * 2 + 1));

    return try genericParse(String)(&buffer, input, _true);
}
