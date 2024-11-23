const std = @import("std");

const core = @import("./core.zig");
pub const heap = @import("./heap.zig");

const AllocatorError = std.mem.Allocator.Error;

const ParserOptions = core.ParserOptions;
const genericParse = core.genericParse;

const DEFAULT_RUNTIME_OUTPUT_SIZE: usize = 10_000;
const DEFAULT_EVAL_BRANCH_QUOTA: usize = 1_000_000;

fn StaticBuffer(comptime T: type, comptime size: usize) type {
    return struct {
        arr: [size]T,
        items: []T,

        const Self = @This();

        pub fn init() Self {
            var obj = Self{
                .arr = .{0} ** size,
                .items = undefined,
            };

            obj.items.len = 0;
            obj.items.ptr = &obj.arr;
            return obj;
        }

        pub fn append(self: *Self, item: T) AllocatorError!void {
            if (self.items.len < size) {
                self.arr[self.items.len] = item;
                self.items.len += 1;
            }
        }

        pub fn appendSlice(self: *Self, items: []const T) AllocatorError!void {
            for (items) |item| {
                if (self.items.len >= size) {
                    break;
                }

                self.arr[self.items.len] = item;
                self.items.len += 1;
            }
        }

        pub fn appendNTimes(self: *Self, item: T, times: usize) AllocatorError!void {
            for (0..times) |_| {
                if (self.items.len >= size) {
                    break;
                }

                self.arr[self.items.len] = item;
                self.items.len += 1;
            }
        }

        pub fn toOwnedSlice(self: *Self) AllocatorError![]T {
            return self.arr[0..self.items.len];
        }
    };
}

fn checkVacancy(comptime Adapter: type) fn (*const Adapter) bool {
    return comptime struct {
        fn f(adapter: *const Adapter) bool {
            return adapter.items.len < adapter.arr.len;
        }
    }.f;
}

pub fn parse(input: []const u8, comptime opt: anytype) [:0]const u8 {
    const opt_struct = comptime ParserOptions.initComptime(opt);
    const Adapter = StaticBuffer(u8, opt_struct.out_size orelse DEFAULT_RUNTIME_OUTPUT_SIZE);
    var buffer = Adapter.init();

    return genericParse(Adapter)(&buffer, input, checkVacancy(Adapter)) catch unreachable;
}

pub fn parseComptime(comptime input: []const u8, comptime opt: anytype) [:0]const u8 {
    const opt_struct = comptime ParserOptions.initComptime(opt);
    @setEvalBranchQuota(opt_struct.branch_quota orelse DEFAULT_EVAL_BRANCH_QUOTA);

    const Adapter = comptime StaticBuffer(u8, opt_struct.out_size orelse input.len * 3);
    comptime var buffer = Adapter.init();

    return comptime genericParse(Adapter)(&buffer, input, checkVacancy(Adapter)) catch unreachable;
}

inline fn parseComptimeDefault(comptime input: []const u8) [:0]const u8 {
    return parseComptime(input, .{});
}

// Test cases

const test_bold = parseComptimeDefault(
    \\The text is <B>bold</>.
    \\
);

test "Bold font (comptime)" {
    try std.testing.expectEqualStrings("The text is \x1b[1mbold\x1b[0m.\n", test_bold);
}

const test_italic = parseComptimeDefault(
    \\The text is <I>italic</>.
    \\
);

test "Italic font (comptime)" {
    try std.testing.expectEqualStrings("The text is \x1b[3mitalic\x1b[0m.\n", test_italic);
}

const test_bold_italic = parseComptimeDefault(
    \\<B;I>bold and italic</>
    \\
);

test "Merge bold and italic font (comptime)" {
    try std.testing.expectEqualStrings("\x1b[1;3mbold and italic\x1b[0m\n", test_bold_italic);
}

const test_triple_merger1 = parseComptimeDefault(
    \\<B;I;RED>styled</> text
    \\<GREEN;B>over here</>
    \\
);

test "Triple merger normal (comptime)" {
    try std.testing.expectEqualStrings("\x1b[1;3;31mstyled\x1b[0m text\n\x1b[32;1mover here\x1b[0m\n", test_triple_merger1);
}

const test_multiple_merger1 = parseComptimeDefault(
    \\<B;I;RED;GREEN;/> styled? no!
);

test "Multiple (under 10) merger with reset (comptime)" {
    try std.testing.expectEqualStrings("\x1b[1;3;31;32;0m styled? no!", test_multiple_merger1);
}

const one_tab = parseComptimeDefault(
    \\Name<!TAB>Age<!TAB>Description
    \\
);

test "Tab once (comptime)" {
    try std.testing.expectEqualStrings("Name\tAge\tDescription\n", one_tab);
}

const five_tabs = parseComptimeDefault(
    \\Start<!TAB*5>tabsssss!
    \\
);

test "5 tabs (comptime)" {
    try std.testing.expectEqualStrings("Start" ++ ("\t" ** 5) ++ "tabsssss!\n", five_tabs);
}

const tabs_x12 = parseComptimeDefault(
    \\Start<!TAB*12>tabs!
    \\
);

test "12 tabs (comptime)" {
    try std.testing.expectEqualStrings("Start" ++ ("\t" ** 12) ++ "tabs!\n", tabs_x12);
}

const fmt_tabs_x300 =
    \\Start<!TAB*300>tabs!
;
const tabs_x300 = parseComptime(fmt_tabs_x300, .{ .out_size = 400 });

test "Leaking test (tabs x300) (comptime)" {
    const str = "Start" ++ ("\t" ** 300) ++ "tabs!";

    try std.testing.expectEqualStrings(str, tabs_x300);
}

const lf_test1 = parseComptimeDefault(
    \\Topic:<!LF>Blah blah...<!LF>
    \\
);

test "Line feed test 1 (comptime)" {
    try std.testing.expectEqualStrings("Topic:\nBlah blah...\n\n", lf_test1);
}

const lf_x3_test1 = parseComptimeDefault(
    \\Topic:<!LF*3>
    \\
    \\
    \\
);

test "Line feed test 2 (comptime)" {
    try std.testing.expectEqualStrings("Topic:" ++ ("\n" ** 6), lf_x3_test1);
}

const cr_test1 = parseComptimeDefault(
    \\That<!CR>This is good!
    \\
);

test "Carriage return test 1 (comptime)" {
    try std.testing.expectEqualStrings("That\rThis is good!\n", cr_test1);
}
