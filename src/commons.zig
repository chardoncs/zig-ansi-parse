const std = @import("std");

pub const ESC = '\x1b';
pub const CSI = '[';

pub const ansi_code_map = std.StaticStringMap([]const u8).initComptime(.{
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

pub const behavioral_code_map = std.StaticStringMap(u8).initComptime(.{
    .{ "TAB", '\t' },
    .{ "CR", '\r' },
    .{ "LF", '\n' },
});

pub const TAG_GROUP_CAPACITY = 171;
pub const SPLIT_CAPACITY = 10;

pub fn assertTypeComptime(comptime Actual: type, comptime Expected: type, comptime name: []const u8) void {
    if (Expected != Actual) {
        @compileError("expect " ++ @typeName(Expected) ++ " as the type of `" ++ name ++ "`, found " ++ @typeName(Actual));
    }
}
