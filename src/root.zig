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
    .{ "DBLU", "21" }, // Double underline
    .{ "NOB", "21" }, // Disable bold
    .{ "NORMAL", "22" }, // Normal intensity (disable bold & faint)
    .{ "NOI", "23" }, // Disable italic and blackletter
    .{ "NOU", "24" }, // Disable underlines
    .{ "NOBLINK", "25" }, // Disable blinking
    .{ "NOREV", "27" }, // Not reversed
    .{ "REVEAL", "28" }, // Disable conceal
    .{ "NOSTRIKE", "29" }, // Disable strikethroughs
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
    .{ "FG", "38" }, // Custom foreground color  TODO: implement check
    .{ "DEFAULT", "39" }, // Default foreground
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
    .{ "BG", "48" }, // Custom background color  TODO: implement check
    .{ "BGDEFAULT", "49" }, // Default background

    .{ "FRAMED", "51" },
    .{ "ENCIRCLED", "52" },
    .{ "OVERLINED", "53" },
    .{ "NOFRAME", "54" }, // Disable frames and circles
    .{ "NOOVERLINE", "55" }, // Disable overlines
    .{ "UCOLOR", "58" }, // Custom underline color   TODO: implement check
    .{ "UDEFAULT", "59" }, // Default underline color
    .{ "SUPER", "73" }, // Superscript
    .{ "SUB", "74" }, // Subscript
    .{ "NOS", "75" }, // Disable superscript and subscript
});

const behavioral_code_map = std.StaticStringMap(u8).initComptime(.{
    .{ "TAB", '\t' },
    .{ "CR", '\r' },
    .{ "LF", '\n' },
});

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

fn assignChar(comptime T: type) fn (*T, *usize, u8) void {
    return comptime struct {
        fn f(arr: *T, cursor: *usize, ch: u8) void {
            arr.*[cursor.*] = ch;
            cursor.* += 1;
        }
    }.f;
}

fn append(comptime T: type) fn (*T, *usize, u8) void {
    return comptime struct {
        fn f(arr: *T, cursor: *usize, ch: u8) void {
            if (cursor.* >= arr.len) {
                return;
            }

            assignChar(T)(arr, cursor, ch);
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

                assignChar(T)(arr, cursor, ch);
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

                assignChar(T)(arr, cursor, ch);
            }
        }
    }.f;
}

const TAG_GROUP_CAPACITY = 171;
const SPLIT_CAPACITY = 10;

/// Parse a format string to ANSI-escapable
pub fn parseComptime(comptime input: []const u8) [:0]const u8 {
    comptime {
        const est_size = input.len * 4; // TODO: Estimate capacity
        var output: [est_size]u8 = .{0} ** est_size;
        const Out = @TypeOf(output);
        var size: usize = 0;

        var i: usize = 0;
        var ch: u8 = undefined;
        var tag: [TAG_GROUP_CAPACITY:0]u8 = .{0} ** TAG_GROUP_CAPACITY;
        var split_arr: [SPLIT_CAPACITY]usize = .{0} ** SPLIT_CAPACITY;

        outer_parse_loop: while (i < input.len and size < output.len) {
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

                            while (j < input.len) {
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

                                j += 1;
                            }
                        },
                        else => {
                            // ANSI
                            var is_closed = false;
                            var ch2: u8 = undefined;
                            var cursor: usize = 0;
                            var split_size = 0;

                            while (j < input.len and cursor < tag.len) {
                                ch2 = input[j];

                                switch (ch2) {
                                    '>' => {
                                        // Tag end
                                        is_closed = true;
                                        break;
                                    },

                                    else => {
                                        if (ch2 == ';' and split_size < split_arr.len) {
                                            split_arr[split_size] = ch2;
                                            split_size += 1;
                                        }

                                        tag[cursor] = ch2;
                                        cursor += 1;
                                    },
                                }

                                j += 1;
                            }

                            if (is_closed) {
                                appendSlice(Out)(&output, &size, &[_]u8{ ESC, CSI });

                                var prev: usize = 0;

                                for (0..split_size) |si| {
                                    const tag_piece = tag[prev..split_arr[si]];
                                    prev = split_arr[si] + 1;

                                    appendSlice(Out)(&output, &size, if (isInteger(tag_piece)) tag_piece else ansi_code_map.get(tag_piece) orelse continue);
                                    append(&output, &size, ';');
                                }

                                const last_tag = tag[prev..];

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
                        '<', '>' => {
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

            i += 1;
        }

        return (output[0..size].* ++ .{0})[0..size :0];
    }
}
