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

const INTERNAL_BRANCH_QUOTA = 1_500_000;

inline fn assertTypeComptime(comptime Actual: type, comptime Expected: type, comptime name: []const u8) void {
    if (Expected != Actual) {
        @compileError("expect " ++ @typeName(Expected) ++ " as the type of `" ++ name ++ "`, found " ++ @typeName(Actual));
    }
}

pub const ParserOptions = struct {
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

pub fn genericParse(comptime List: type) fn (*List, []const u8, comptime fn (*const List) bool) Allocator.Error![:0]const u8 {
    return comptime struct {
        fn f(buffer: *List, input: []const u8, comptime hasVacancy: fn (*const List) bool) Allocator.Error![:0]const u8 {
            var i: usize = 0;
            var ch: u8 = undefined;
            var tag: [TAG_GROUP_CAPACITY:0]u8 = .{0} ** TAG_GROUP_CAPACITY;
            var split_arr: [SPLIT_CAPACITY]usize = .{0} ** SPLIT_CAPACITY;

            outer_parse_loop: while (i < input.len and hasVacancy(buffer)) : (i += 1) {
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
                                            try buffer.appendNTimes(code, times orelse 1);

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
                                    try buffer.appendSlice(&[_]u8{ ESC, CSI });

                                    var prev: usize = 0;

                                    for (0..split_size) |si| {
                                        const tag_piece = tag[prev..split_arr[si]];
                                        prev = split_arr[si] + 1;

                                        try buffer.appendSlice(if (isNumbersOnly(tag_piece)) tag_piece else ansi_code_map.get(tag_piece) orelse continue);
                                        try buffer.append(';');
                                    }

                                    const last_tag = tag[prev..cursor];

                                    if (isNumbersOnly(last_tag)) {
                                        try buffer.appendSlice(last_tag);
                                    } else {
                                        if (ansi_code_map.get(last_tag)) |last_code| {
                                            try buffer.appendSlice(last_code);
                                        }
                                    }
                                    try buffer.append('m');

                                    i = j;
                                    ch = ch2;
                                } else {
                                    try buffer.append(ch);
                                }
                            },
                        }
                    },

                    '\\' => {
                        // Escape
                        const j = i + 1;
                        if (j >= input.len) {
                            try buffer.append(ch);
                            break :outer_parse_loop;
                        }

                        switch (input[j]) {
                            '<', '>', '\\' => {
                                i = j;
                                ch = input[i];
                                try buffer.append(ch);
                            },
                            else => {
                                try buffer.append(ch);
                            },
                        }
                    },

                    else => {
                        // Regular character
                        try buffer.append(ch);
                    },
                }
            }

            const size = buffer.items.len;
            try buffer.append(0);
            return (try buffer.toOwnedSlice())[0..size :0];
        }
    }.f;
}

fn isNumbersOnly(input: []const u8) bool {
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
