const std = @import("std");

const Allocator = std.mem.Allocator;

const ESC = '\x1b';
const CSI = '[';

const ansi_code_map = std.StaticStringMap([]const u8).initComptime(.{
    .{ "/", "0" }, // Reset
    .{ "B", "1" }, // Bold
    .{ "FAINT", "2" }, // Faint
    .{ "I", "3" }, // Italic
    .{ "U", "4" }, // Underline
    .{ "SBLINK", "5" }, // Slow blink
    .{ "RBLINK", "6" }, // Rapid blink
    .{ "INVERT", "7" }, // Swap foreground with background (limited support)
    .{ "CONCEAL", "8" }, // Conceal (limited support)
    .{ "/REVEAL", "8" },
    .{ "STRIKE", "9" }, // Strikethrough (limited support)
    .{ "FONT", "10" }, // Default font
    .{ "FONT1", "11" },
    .{ "FONT2", "12" },
    .{ "FONT3", "13" },
    .{ "FONT4", "14" },
    .{ "FONT5", "15" },
    .{ "FONT6", "16" },
    .{ "FONT7", "17" },
    .{ "FONT8", "18" },
    .{ "FONT9", "19" },
    .{ "FRAKTUR", "20" }, // Fraktur font (very limited support)
    .{ "DBLU", "21" }, // Double underline (limited support)
    .{ "/B", "22" }, // Normal intensity (disable bold & faint)
    .{ "/I", "23" }, // Disable italic and blackletter
    .{ "/U", "24" }, // Disable underlines
    .{ "/BLINK", "25" }, // Disable blinking
    .{ "/REV", "27" }, // Not reversed
    .{ "REVEAL", "28" }, // Disable conceal
    .{ "/CONCEAL", "28" },
    .{ "/STRIKE", "29" }, // Disable strikethroughs
    // Foreground
    .{ "BLACK", "30" }, // Black
    .{ "RED", "31" }, // Red
    .{ "GREEN", "32" }, // Green
    .{ "YELLOW", "33" }, // Yellow
    .{ "BLUE", "34" }, // Blue
    .{ "MAGENTA", "35" }, // Magenta
    .{ "CYAN", "36" }, // Cyan
    .{ "WHITE", "37" }, // White
    .{ "GRAY", "90" }, // Bright black (gray)
    .{ "GREY", "90" },
    .{ "BRBLACK", "90" },
    .{ "BRRED", "91" }, // Bright red
    .{ "BRGREEN", "92" }, // Bright green
    .{ "BRYELLOW", "93" }, // Bright yellow
    .{ "BRBLUE", "94" }, // Bright blue
    .{ "BRMAGENTA", "95" }, // Bright magenta
    .{ "BRCYAN", "96" }, // Bright cyan
    .{ "BRWHITE", "97" }, // Bright white
    .{ "FG", "38" }, // Custom foreground color
    .{ "FGDEFAULT", "39" }, // Default foreground
    // Background
    .{ "BGBLACK", "40" }, // Black
    .{ "BGRED", "41" }, // Red
    .{ "BGGREEN", "42" }, // Green
    .{ "BGYELLOW", "43" }, // Yellow
    .{ "BGBLUE", "44" }, // Blue
    .{ "BGMAGENTA", "45" }, // Magenta
    .{ "BGCYAN", "46" }, // Cyan
    .{ "BGWHITE", "47" }, // White
    .{ "BGGRAY", "100" }, // Bright black (gray)
    .{ "BGGREY", "100" },
    .{ "BGBRBLACK", "100" },
    .{ "BGBRRED", "101" }, // Bright red
    .{ "BGBRGREEN", "102" }, // Bright green
    .{ "BGBRYELLOW", "103" }, // Bright yellow
    .{ "BGBRBLUE", "104" }, // Bright blue
    .{ "BGBRMAGENTA", "105" }, // Bright magenta
    .{ "BGBRCYAN", "106" }, // Bright cyan
    .{ "BGBRWHITE", "107" }, // Bright white
    .{ "BG", "48" }, // Custom background color
    .{ "BGDEFAULT", "49" }, // Default background

    .{ "FRAMED", "51" },
    .{ "ENCIRCLED", "52" },
    .{ "OVERLINED", "53" },
    .{ "/FRAMED", "54" }, // Disable frames and circles
    .{ "/OVERLINED", "55" }, // Disable overlines
    .{ "UCOLOR", "58" }, // Custom underline color
    .{ "UDEFAULT", "59" }, // Default underline color
    .{ "SUPER", "73" }, // Superscript
    .{ "SUB", "74" }, // Subscript
    .{ "/SUPER", "75" }, // Disable superscript and subscript
    .{ "/SUB", "75" },
});

const behavioral_code_map = std.StaticStringMap(u8).initComptime(.{
    .{ "TAB", '\t' },
    .{ "CR", '\r' },
    .{ "LF", '\n' },
});

const TAG_GROUP_CAPACITY = 171;
const SPLIT_CAPACITY = 10;

const DEFAULT_BRANCH_QUOTA = 200_000;
const INTERNAL_BRANCH_QUOTA = 1_000_000;

inline fn assertTypeComptime(comptime Actual: type, comptime Expected: type, comptime name: []const u8) void {
    if (Expected != Actual) {
        @compileError("expect " ++ @typeName(Expected) ++ " as the type of `" ++ name ++ "`, found " ++ @typeName(Actual));
    }
}

const ParserOptions = struct {
    branch_quota: ?u32,
    out_size: ?usize,

    pub fn initComptime(comptime opt: anytype) ParserOptions {
        const OptType = @TypeOf(opt);
        const opt_type_info = @typeInfo(OptType);
        if (opt_type_info != .Struct) {
            @compileError("expect a struct as options, found " ++ @typeName(OptType));
        }

        const fields = opt_type_info.Struct.fields;

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

/// Parse a format string to ANSI-escapable
pub fn parseComptime(comptime input: []const u8, comptime opt: anytype) [:0]const u8 {
    const opt_struct = ParserOptions.initComptime(opt);

    comptime {
        @setEvalBranchQuota(opt_struct.branch_quota orelse DEFAULT_BRANCH_QUOTA);
        const est_size = opt_struct.out_size orelse (input.len * 4);
        var output: [est_size]u8 = .{0} ** est_size;
        const Out = @TypeOf(output);
        var size: usize = 0;

        var i: usize = 0;
        var ch: u8 = undefined;
        var tag: [TAG_GROUP_CAPACITY:0]u8 = .{0} ** TAG_GROUP_CAPACITY;
        var split_arr: [SPLIT_CAPACITY]usize = .{0} ** SPLIT_CAPACITY;

        outer_parse_loop: while (i < input.len and size < output.len) : (i += 1) {
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
                            var cursor: usize = 0;
                            var ch2: u8 = undefined;
                            var parse_times = false;

                            while (j < input.len) : (j += 1) {
                                ch2 = input[j];

                                switch (ch2) {
                                    '*' => {
                                        parse_times = true;
                                    },

                                    '>' => {
                                        tag[cursor] = 0;
                                        const code = behavioral_code_map.get(tag[0..cursor]) orelse break;
                                        appendNTimes(Out)(&output, &size, code, times orelse 1);

                                        i = j;
                                        ch = ch2;
                                        break;
                                    },

                                    else => {
                                        if (parse_times) {
                                            if (ch2 >= '0' and ch2 <= '9') {
                                                times = (times orelse 0) * 10 + @as(usize, @intCast(ch2 - '0'));
                                            }
                                        } else if (cursor < tag.len) {
                                            tag[cursor] = ch2;
                                            cursor += 1;
                                        }
                                    },
                                }
                            }
                        },
                        else => {
                            // ANSI
                            var is_closed = false;
                            var ch2: u8 = undefined;
                            var cursor: usize = 0;
                            var split_size: usize = 0;

                            while (j < input.len and cursor < tag.len) : (j += 1) {
                                ch2 = input[j];

                                switch (ch2) {
                                    '>' => {
                                        // Tag end
                                        is_closed = true;
                                        break;
                                    },

                                    else => {
                                        if (ch2 == ';' and split_size < split_arr.len) {
                                            split_arr[split_size] = cursor;
                                            split_size += 1;
                                        }

                                        tag[cursor] = ch2;
                                        cursor += 1;
                                    },
                                }
                            }

                            if (is_closed) {
                                appendSlice(Out)(&output, &size, &[_]u8{ ESC, CSI });

                                var prev: usize = 0;

                                for (0..split_size) |si| {
                                    const tag_piece = tag[prev..split_arr[si]];
                                    prev = split_arr[si] + 1;

                                    appendSlice(Out)(&output, &size, if (isInteger(tag_piece)) tag_piece else ansi_code_map.get(tag_piece) orelse continue);
                                    append(Out)(&output, &size, ';');
                                }

                                const last_tag = tag[prev..cursor];

                                if (isInteger(last_tag)) {
                                    appendSlice(Out)(&output, &size, last_tag);
                                } else {
                                    if (ansi_code_map.get(last_tag)) |last_code| {
                                        appendSlice(Out)(&output, &size, last_code);
                                    }
                                }
                                append(Out)(&output, &size, 'm');

                                i = j;
                                ch = ch2;
                            } else {
                                append(Out)(&output, &size, ch);
                            }
                        },
                    }
                },

                '\\' => {
                    // Escape
                    const j = i + 1;
                    if (j >= input.len) {
                        append(Out)(&output, &size, ch);
                        break :outer_parse_loop;
                    }

                    switch (input[j]) {
                        '<', '>', '\\' => {
                            i = j;
                            ch = input[i];
                            append(Out)(&output, &size, ch);
                        },
                        else => {
                            append(Out)(&output, &size, ch);
                        },
                    }
                },

                else => {
                    // Regular character
                    append(Out)(&output, &size, ch);
                },
            }
        }

        return (output[0..size].* ++ .{0})[0..size :0];
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

fn append(comptime T: type) fn (*T, *usize, u8) void {
    return comptime struct {
        fn f(arr: *T, cursor: *usize, ch: u8) void {
            if (cursor.* >= arr.len) {
                return;
            }

            arr.*[cursor.*] = ch;
            cursor.* += 1;
        }
    }.f;
}

fn appendSlice(comptime T: type) fn (*T, *usize, []const u8) void {
    return comptime struct {
        fn f(arr: *T, cursor: *usize, chs: []const u8) void {
            for (chs) |ch| {
                if (cursor.* >= arr.len) {
                    break;
                }

                arr.*[cursor.*] = ch;
                cursor.* += 1;
            }
        }
    }.f;
}

fn appendNTimes(comptime T: type) fn (*T, *usize, u8, usize) void {
    return comptime struct {
        fn f(arr: *T, cursor: *usize, ch: u8, times: usize) void {
            for (0..times) |_| {
                if (cursor.* >= arr.len) {
                    break;
                }

                arr.*[cursor.*] = ch;
                cursor.* += 1;
            }
        }
    }.f;
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
