const std = @import("std");

const commons = @import("./commons.zig");

const DEFAULT_BRANCH_QUOTA = 200_000;
const INTERNAL_BRANCH_QUOTA = 1_000_000;

pub const ParserOptions = struct {
    branch_quota: ?u32,
    out_size: ?usize,

    pub fn initComptime(comptime opt: anytype) ParserOptions {
        const OptType = @TypeOf(opt);
        const opt_type_info = @typeInfo(OptType);
        if (opt_type_info != .@"struct") {
            @compileError("expect a struct as options, found " ++ @typeName(OptType));
        }

        const fields = opt_type_info.@"struct".fields;

        comptime var out_struct = ParserOptions{
            .branch_quota = null,
            .out_size = null,
        };

        @setEvalBranchQuota(INTERNAL_BRANCH_QUOTA);
        inline for (fields) |field| {
            if (@hasField(ParserOptions, field.name)) {
                @field(out_struct, field.name) = @field(opt, field.name);
            }
        }

        return out_struct;
    }
};

fn StaticArrayProxy(hard_size: usize) type {
    return struct {
        ptr: [hard_size]u8,

        len: usize,
        capacity: usize,

        const Self = @This();

        pub fn append(self: *Self, ch: u8) void {
            if (self.len >= self.capacity) {
                return;
            }

            self.ptr[self.len] = ch;
            self.len += 1;
        }

        pub fn appendSlice(self: *Self, chs: []const u8) void {
            for (chs) |ch| {
                if (self.len >= self.capacity) {
                    break;
                }

                self.ptr[self.len] = ch;
                self.len += 1;
            }
        }

        pub fn appendNTimes(self: *Self, ch: u8, times: usize) void {
            for (0..times) |_| {
                if (self.len >= self.capacity) {
                    break;
                }

                self.ptr[self.len] = ch;
                self.len += 1;
            }
        }
    };
}

/// Parse a format string to ANSI-escapable
pub fn parseComptime(comptime input: []const u8, comptime opt: anytype) [:0]const u8 {
    const opt_struct = ParserOptions.initComptime(opt);

    comptime {
        @setEvalBranchQuota(opt_struct.branch_quota orelse DEFAULT_BRANCH_QUOTA);
        const est_size = opt_struct.out_size orelse (input.len * 4);

        var arr = StaticArrayProxy(est_size){
            .ptr = .{0} ** est_size,
            .len = 0,
            .capacity = est_size,
        };

        var i: usize = 0;
        var ch: u8 = undefined;
        var tag: [commons.TAG_GROUP_CAPACITY:0]u8 = .{0} ** commons.TAG_GROUP_CAPACITY;
        var split_arr: [commons.SPLIT_CAPACITY]usize = .{0} ** commons.SPLIT_CAPACITY;

        outer_parse_loop: while (i < input.len and arr.len < arr.capacity) : (i += 1) {
            ch = input[i];

            switch (ch) {
                '<' => {
                    // Tag start
                    var j = i + 1;
                    switch (input[j]) {
                        '!' => {
                            // Behavioral
                            j += 1;
                            var times: ?usize = null;
                            var k: usize = 0;
                            var ch2: u8 = undefined;
                            var parse_times = false;

                            while (j < input.len) : (j += 1) {
                                ch2 = input[j];

                                switch (ch2) {
                                    '*' => {
                                        parse_times = true;
                                    },

                                    '>' => {
                                        tag[k] = 0;
                                        const code = commons.behavioral_code_map.get(tag[0..k]) orelse break;
                                        arr.appendNTimes(code, times orelse 1);

                                        i = j;
                                        ch = ch2;
                                        break;
                                    },

                                    else => {
                                        if (parse_times) {
                                            if (ch2 >= '0' and ch2 <= '9') {
                                                times = (times orelse 0) * 10 + @as(usize, @intCast(ch2 - '0'));
                                            }
                                        } else if (k < tag.len) {
                                            tag[k] = ch2;
                                            k += 1;
                                        }
                                    },
                                }
                            }
                        },
                        else => {
                            // ANSI
                            var is_closed = false;
                            var ch2: u8 = undefined;
                            var k: usize = 0;
                            var split_size: usize = 0;

                            while (j < input.len and k < tag.len) : (j += 1) {
                                ch2 = input[j];

                                switch (ch2) {
                                    '>' => {
                                        // Tag end
                                        is_closed = true;
                                        break;
                                    },

                                    else => {
                                        if (ch2 == ';' and split_size < split_arr.len) {
                                            split_arr[split_size] = k;
                                            split_size += 1;
                                        }

                                        tag[k] = ch2;
                                        k += 1;
                                    },
                                }
                            }

                            if (is_closed) {
                                arr.appendSlice(&[_]u8{ commons.ESC, commons.CSI });

                                var prev: usize = 0;

                                for (0..split_size) |si| {
                                    const tag_piece = tag[prev..split_arr[si]];
                                    prev = split_arr[si] + 1;

                                    arr.appendSlice(if (isInteger(tag_piece)) tag_piece else commons.ansi_code_map.get(tag_piece) orelse continue);
                                    arr.append(';');
                                }

                                const last_tag = tag[prev..k];

                                if (isInteger(last_tag)) {
                                    arr.appendSlice(last_tag);
                                } else {
                                    if (commons.ansi_code_map.get(last_tag)) |last_code| {
                                        arr.appendSlice(last_code);
                                    }
                                }
                                arr.append('m');

                                i = j;
                                ch = ch2;
                            } else {
                                arr.append(ch);
                            }
                        },
                    }
                },

                '\\' => {
                    // Escape
                    const j = i + 1;
                    if (j >= input.len) {
                        arr.append(ch);
                        break :outer_parse_loop;
                    }

                    switch (input[j]) {
                        '<', '>', '\\' => {
                            i = j;
                            ch = input[i];
                            arr.append(ch);
                        },
                        else => {
                            arr.append(ch);
                        },
                    }
                },

                else => {
                    // Regular character
                    arr.append(ch);
                },
            }
        }

        return (arr.ptr[0..arr.len].* ++ .{0})[0..arr.len:0];
    }
}

inline fn parseComptimeDefault(comptime input: []const u8) [:0]const u8 {
    return parseComptime(input, .{});
}

fn isInteger(input: []const u8) bool {
    for (input) |ch| {
        switch (ch) {
            '0'...'9' => {},
            else => {
                return false;
            },
        }
    }

    return true;
}

// Test cases

test "Bold font (comptime)" {
    const test_bold = comptime parseComptimeDefault(
        \\The text is <B>bold</>.
        \\
    );
    try std.testing.expectEqualStrings("The text is \x1b[1mbold\x1b[0m.\n", test_bold);
}

test "Italic font (comptime)" {
    const test_italic = comptime parseComptimeDefault(
        \\The text is <I>italic</>.
        \\
    );
    try std.testing.expectEqualStrings("The text is \x1b[3mitalic\x1b[0m.\n", test_italic);
}

test "Merge bold and italic font (comptime)" {
    const test_bold_italic = comptime parseComptimeDefault(
        \\<B;I>bold and italic</>
        \\
    );

    try std.testing.expectEqualStrings("\x1b[1;3mbold and italic\x1b[0m\n", test_bold_italic);
}

test "Triple merger normal (comptime)" {
    const test_triple_merger1 = comptime parseComptimeDefault(
        \\<B;I;RED>styled</> text
        \\<GREEN;B>over here</>
        \\
    );

    try std.testing.expectEqualStrings("\x1b[1;3;31mstyled\x1b[0m text\n\x1b[32;1mover here\x1b[0m\n", test_triple_merger1);
}

test "Multiple (under 10) merger with reset (comptime)" {
    const test_multiple_merger1 = comptime parseComptimeDefault(
        \\<B;I;RED;GREEN;/> styled? no!
    );

    try std.testing.expectEqualStrings("\x1b[1;3;31;32;0m styled? no!", test_multiple_merger1);
}

test "Tab once (comptime)" {
    const one_tab = comptime parseComptimeDefault(
        \\Name<!TAB>Age<!TAB>Description
        \\
    );

    try std.testing.expectEqualStrings("Name\tAge\tDescription\n", one_tab);
}

test "5 tabs (comptime)" {
    const five_tabs = comptime parseComptimeDefault(
        \\Start<!TAB*5>tabsssss!
        \\
    );

    try std.testing.expectEqualStrings("Start" ++ ("\t" ** 5) ++ "tabsssss!\n", five_tabs);
}

test "12 tabs (comptime)" {
    const tabs_x12 = comptime parseComptimeDefault(
        \\Start<!TAB*12>tabs!
        \\
    );

    try std.testing.expectEqualStrings("Start" ++ ("\t" ** 12) ++ "tabs!\n", tabs_x12);
}

test "Leaking test (tabs x300) (comptime)" {
    const fmt_tabs_x300 =
        \\Start<!TAB*300>tabs!
    ;
    const tabs_x300 = comptime parseComptime(fmt_tabs_x300, .{ .out_size = 400 });

    const str = "Start" ++ ("\t" ** 300) ++ "tabs!";

    try std.testing.expectEqualStrings(str, tabs_x300);
}

test "Line feed test 1 (comptime)" {
    const lf_test1 = comptime parseComptimeDefault(
        \\Topic:<!LF>Blah blah...<!LF>
        \\
    );


    try std.testing.expectEqualStrings("Topic:\nBlah blah...\n\n", lf_test1);
}

test "Line feed test 2 (comptime)" {
    const lf_x3_test1 = comptime parseComptimeDefault(
        \\Topic:<!LF*3>
        \\
        \\
        \\
    );

    try std.testing.expectEqualStrings("Topic:" ++ ("\n" ** 6), lf_x3_test1);
}

test "Carriage return test 1 (comptime)" {
    const cr_test1 = comptime parseComptimeDefault(
        \\That<!CR>This is good!
        \\
    );

    try std.testing.expectEqualStrings("That\rThis is good!\n", cr_test1);
}
