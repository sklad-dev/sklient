const std = @import("std");

// Screen management
pub const NEW_SCREEN = "\x1b[?1049h\x1b[2J\x1b[H";
pub const EXIT_SCREEN = "\x1b[2J\x1b[H\x1b[?1049l";
pub const CLEAR_SCREEN = "\x1b[H\x1b[2J";
pub const HOME = "\x1b[H";
pub const HIDE_CURSOR = "\x1b[?25l";
pub const SHOW_CURSOR = "\x1b[?25h";

// Line/cursor manipulation
pub const ERASE_LINE = "\x1b[2K";
pub const MOVE_UP = "\x1b[1A";
pub const MOVE_DOWN = "\x1b[1B";
pub const SAVE_CURSOR = "\x1b[s";
pub const RESTORE_CURSOR = "\x1b[u";

// Text styling
pub const HIGHLIGHT = "\x1b[7m";
pub const UNDERLINE_START = "\x1b[4m";
pub const UNDERLINE_END = "\x1b[24m";
pub const BOLD_START = "\x1b[1m";
pub const BOLD_END = "\x1b[22m";
pub const RESET = "\x1b[0m";
pub const DIM = "\x1b[2m";
pub const DIM_END = "\x1b[22m";

// Colors
pub const GREY = "\x1b[90m";
pub const LIGHT_GREY_BG = "\x1b[48;5;236m";
pub const CYAN = "\x1b[36m";
pub const GREEN = "\x1b[32m";
pub const YELLOW = "\x1b[33m";
pub const WHITE = "\x1b[37m";

// Box-drawing characters (Unicode)
pub const BOX_HORIZONTAL = "─";
pub const BOX_VERTICAL = "│";
pub const BOX_TOP_LEFT = "┌";
pub const BOX_TOP_RIGHT = "┐";
pub const BOX_BOTTOM_LEFT = "└";
pub const BOX_BOTTOM_RIGHT = "┘";
pub const BOX_T_DOWN = "┬";
pub const BOX_T_UP = "┴";
pub const BOX_T_RIGHT = "├";
pub const BOX_T_LEFT = "┤";
pub const BOX_CROSS = "┼";

// Helper functions for cursor positioning
pub fn moveTo(buf: []u8, row: u16, col: u16) []const u8 {
    const len = std.fmt.bufPrint(buf, "\x1b[{d};{d}H", .{ row, col }) catch return "";
    return buf[0..len.len];
}

pub fn moveToRow(buf: []u8, row: u16) []const u8 {
    const len = std.fmt.bufPrint(buf, "\x1b[{d};1H", .{row}) catch return "";
    return buf[0..len.len];
}
