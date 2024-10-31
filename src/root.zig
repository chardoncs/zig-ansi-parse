const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const ESC = '\x1b';
const CSI = '[';

const ansi_code_map = std.StaticStringMap(u8).initComptime(.{
    .{ "/", 0 }, // Reset
    .{ "B", 1 }, // Bold
    .{ "FAINT", 2 }, // Faint
    .{ "I", 3 }, // Italic
    .{ "U", 4 }, // Underline
    .{ "SBLINK", 5 }, // Slow blink
    .{ "RBLINK", 6 }, // Rapid blink
    .{ "INVERT", 7 }, // Swap foreground with background (limited support)
    .{ "CONCEAL", 8 }, // Conceal (limited support)
    .{ "STRIKE", 9 }, // Strikethrough (limited support)
    .{ "F", 10 }, // Default font
    .{ "F1", 11 },
    .{ "F2", 12 },
    .{ "F3", 13 },
    .{ "F4", 14 },
    .{ "F5", 15 },
    .{ "F6", 16 },
    .{ "F7", 17 },
    .{ "F8", 18 },
    .{ "F9", 19 },
    .{ "FRAKTUR", 20 }, // Fraktur font (very limited support)
    .{ "DBLU", 21 }, // Double underline
    .{ "NOB", 21 }, // Disable bold
    .{ "NORMAL", 22 }, // Normal intensity (disable bold & faint)
    .{ "NOI", 23 }, // Disable italic and blackletter
    .{ "NOU", 24 }, // Disable underlines
    .{ "NOBLINK", 25 }, // Disable blinking
    .{ "NOREV", 27 }, // Not reversed
    .{ "REVEAL", 28 }, // Disable conceal
    .{ "NOSTRIKE", 29 }, // Disable strikethroughs
    // Foreground
    .{ "BLACK", 30 }, // Black
    .{ "RED", 31 }, // Red
    .{ "GREEN", 32 }, // Green
    .{ "YELLOW", 33 }, // Yellow
    .{ "BLUE", 34 }, // Blue
    .{ "MAGENTA", 35 }, // Magenta
    .{ "CYAN", 36 }, // Cyan
    .{ "WHITE", 37 }, // White
    .{ "GRAY", 90 }, // Bright black (gray)
    .{ "GREY", 90 },
    .{ "BRBLACK", 90 },
    .{ "BRRED", 91 }, // Bright red
    .{ "BRGREEN", 92 }, // Bright green
    .{ "BRYELLOW", 93 }, // Bright yellow
    .{ "BRBLUE", 94 }, // Bright blue
    .{ "BRMAGENTA", 95 }, // Bright magenta
    .{ "BRCYAN", 96 }, // Bright cyan
    .{ "BRWHITE", 97 }, // Bright white
    .{ "FG", 38 }, // Custom foreground color  TODO: implement check
    .{ "DEFAULT", 39 }, // Default foreground
    // Background
    .{ "BGBLACK", 40 }, // Black
    .{ "BGRED", 41 }, // Red
    .{ "BGGREEN", 42 }, // Green
    .{ "BGYELLOW", 43 }, // Yellow
    .{ "BGBLUE", 44 }, // Blue
    .{ "BGMAGENTA", 45 }, // Magenta
    .{ "BGCYAN", 46 }, // Cyan
    .{ "BGWHITE", 47 }, // White
    .{ "BGGRAY", 100 }, // Bright black (gray)
    .{ "BGGREY", 100 },
    .{ "BGBRBLACK", 100 },
    .{ "BGBRRED", 101 }, // Bright red
    .{ "BGBRGREEN", 102 }, // Bright green
    .{ "BGBRYELLOW", 103 }, // Bright yellow
    .{ "BGBRBLUE", 104 }, // Bright blue
    .{ "BGBRMAGENTA", 105 }, // Bright magenta
    .{ "BGBRCYAN", 106 }, // Bright cyan
    .{ "BGBRWHITE", 107 }, // Bright white
    .{ "BG", 48 }, // Custom background color  TODO: implement check
    .{ "BGDEFAULT", 49 }, // Default background

    .{ "FRAMED", 51 },
    .{ "ENCIRCLED", 52 },
    .{ "OVERLINED", 53 },
    .{ "NOFRAME", 54 }, // Disable frames and circles
    .{ "NOOVERLINE", 55 }, // Disable overlines
    .{ "UCOLOR", 58 }, // Custom underline color   TODO: implement check
    .{ "UDEFAULT", 59 }, // Default underline color
    .{ "SUPER", 73 }, // Superscript
    .{ "SUB", 74 }, // Subscript
    .{ "NOS", 75 }, // Disable superscript and subscript
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

fn toInteger(input: []const u8) u32 {
    var output: u32 = 0;

    for (input) |ch| {
        switch (ch) {
            '0'...'9' => {
                output = output * 10 + @as(u32, @intCast(ch - '0'));
            },
            else => {},
        }
    }

    return output;
}

/// Parse a format string to ANSI-escapable
pub fn parse(allocator: Allocator, input: []const u8) Allocator.Error![]const u8 {
    const output = try ArrayList(u8).initCapacity(allocator, input.len * 1.5);

    var i: usize = 0;
    var ch: u8 = undefined;
    var tag = [171:0]u8{};
    var split_arr = [10]usize{};

    outer_parse_loop: while (i < input.len) {
        ch = input[i];

        switch (ch) {
            '<' => {
                // Tag start
                var j = i + 1;
                switch (input[j]) {
                    '!' => {
                        // Behavioral
                        j += 1;
                        var times: u32 = 1;

                        while (j < input.len) {
                            // TODO

                            j += 1;
                        }
                    },
                    else => {
                        // ANSI
                        var is_closed = false;
                        var ch2: u8 = undefined;
                        var cursor: usize = 0;
                        var split_size: usize = 0;

                        while (j < input.len and cursor < tag.len) {
                            ch2 = input[j];

                            switch (ch2) {
                                '>' => {
                                    // Tag end
                                    is_closed = true;
                                    tag[cursor] = 0;
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
                            try output.appendSlice(.{ ESC, CSI });

                            var prev: usize = 0;

                            for (split_arr) |delim_i| {
                                const tag_piece = tag[prev..delim_i];
                                try output.appendSlice(if (isInteger(tag_piece)) tag_piece else .{ansi_code_map.get(tag_piece)} orelse continue);
                                prev = delim_i + 1;
                            }

                            const last_tag = tag[prev..];
                            if (isInteger(last_tag)) {
                                try output.appendSlice(last_tag);
                            } else {
                                if (ansi_code_map.get(last_tag)) |last_code| {
                                    try output.append(last_code);
                                }
                            }

                            try output.append('m');

                            i = j;
                            ch = ch2;
                        } else {
                            try output.append(ch);
                        }
                    },
                }
            },

            '\\' => {
                // Escape
                const j = i + 1;
                if (j >= input.len) {
                    try output.append(ch);
                    break :outer_parse_loop;
                }

                switch (input[j]) {
                    '<', '>' => {
                        i = j;
                        ch = input[i];
                        try output.append(ch);
                    },
                    else => {
                        try output.append(ch);
                    },
                }
            },

            else => {
                // Regular character
                try output.append(ch);
            },
        }

        i += 1;
    }

    return try output.toOwnedSlice();
}
