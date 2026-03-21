const std = @import("std");
const codes = @import("codes.zig");

const TermSize = struct { width: u16, height: u16 };

/// Layout manager for the TUI interface.
/// Handles drawing borders, managing sections, and coordinate calculations.
pub const Layout = struct {
    width: u16,
    height: u16,
    query_area_height: u16,
    results_start_row: u16,
    results_height: u16,
    writer: *std.Io.Writer,

    const QUERY_AREA_HEIGHT: u16 = 3; // Border + input line + border
    const MIN_WIDTH: u16 = 40;
    const MIN_HEIGHT: u16 = 10;
    const TITLE = " sklient ";
    const MODE_INDICATOR_WIDTH: u16 = 10;

    pub fn init(writer: *std.Io.Writer) Layout {
        const size = terminalSize() orelse TermSize{ .width = 80, .height = 24 };
        const width = @max(size.width, MIN_WIDTH);
        const height = @max(size.height, MIN_HEIGHT);

        return .{
            .width = width,
            .height = height,
            .query_area_height = QUERY_AREA_HEIGHT,
            .results_start_row = QUERY_AREA_HEIGHT + 1,
            .results_height = height - QUERY_AREA_HEIGHT - 2, // -2 for bottom border
            .writer = writer,
        };
    }

    pub fn refresh(self: *Layout) void {
        const size = terminalSize() orelse return;
        self.width = @max(size.width, MIN_WIDTH);
        self.height = @max(size.height, MIN_HEIGHT);
        self.results_height = self.height - self.query_area_height - 2;
    }

    /// Draw the complete frame with borders
    pub fn drawFrame(self: *Layout, mode: Mode) !void {
        try self.writer.writeAll(codes.CLEAR_SCREEN);
        try self.writer.writeAll(codes.HIDE_CURSOR);

        // Top border with title
        try self.drawTopBorder(mode);

        // Empty query input line
        try self.drawEmptyQueryLine();

        // Separator between query and results
        try self.drawSeparator();

        // Results area (empty initially)
        try self.drawEmptyResultsArea();

        // Bottom border
        try self.drawBottomBorder();

        // Position cursor in query input area
        try self.positionCursorForInput();
        try self.writer.writeAll(codes.SHOW_CURSOR);
    }

    fn drawTopBorder(self: *Layout, mode: Mode) !void {
        try self.writer.writeAll(codes.CYAN);
        try self.writer.writeAll(codes.BOX_TOP_LEFT);

        // Title
        try self.writer.writeAll(codes.BOLD_START);
        try self.writer.writeAll(TITLE);
        try self.writer.writeAll(codes.BOLD_END);

        // Fill remaining width
        const title_len: u16 = @intCast(TITLE.len);
        const mode_str = switch (mode) {
            .tui => " [TUI] ",
            .raw => " [RAW] ",
        };
        const mode_len: u16 = @intCast(mode_str.len);
        const fill_count = self.width -| title_len -| mode_len -| 2;

        for (0..fill_count) |_| {
            try self.writer.writeAll(codes.BOX_HORIZONTAL);
        }

        // Mode indicator
        try self.writer.writeAll(codes.YELLOW);
        try self.writer.writeAll(mode_str);
        try self.writer.writeAll(codes.CYAN);
        try self.writer.writeAll(codes.BOX_TOP_RIGHT);
        try self.writer.writeAll(codes.RESET);
        try self.writer.writeByte('\n');
    }

    fn drawEmptyQueryLine(self: *Layout) !void {
        try self.writer.writeAll(codes.CYAN);
        try self.writer.writeAll(codes.BOX_VERTICAL);
        try self.writer.writeAll(codes.RESET);

        // Fill with spaces
        for (0..self.width - 2) |_| {
            try self.writer.writeByte(' ');
        }

        try self.writer.writeAll(codes.CYAN);
        try self.writer.writeAll(codes.BOX_VERTICAL);
        try self.writer.writeAll(codes.RESET);
        try self.writer.writeByte('\n');
    }

    fn drawSeparator(self: *Layout) !void {
        try self.writer.writeAll(codes.CYAN);
        try self.writer.writeAll(codes.BOX_T_RIGHT);

        for (0..self.width - 2) |_| {
            try self.writer.writeAll(codes.BOX_HORIZONTAL);
        }

        try self.writer.writeAll(codes.BOX_T_LEFT);
        try self.writer.writeAll(codes.RESET);
        try self.writer.writeByte('\n');
    }

    fn drawEmptyResultsArea(self: *Layout) !void {
        for (0..self.results_height) |_| {
            try self.writer.writeAll(codes.CYAN);
            try self.writer.writeAll(codes.BOX_VERTICAL);
            try self.writer.writeAll(codes.RESET);

            for (0..self.width - 2) |_| {
                try self.writer.writeByte(' ');
            }

            try self.writer.writeAll(codes.CYAN);
            try self.writer.writeAll(codes.BOX_VERTICAL);
            try self.writer.writeAll(codes.RESET);
            try self.writer.writeByte('\n');
        }
    }

    fn drawBottomBorder(self: *Layout) !void {
        try self.writer.writeAll(codes.CYAN);
        try self.writer.writeAll(codes.BOX_BOTTOM_LEFT);

        // Status/help text
        const help_text = " Ctrl+T: toggle mode | Ctrl+C: exit ";
        const help_len: u16 = @intCast(help_text.len);

        for (0..(self.width -| help_len -| 2) / 2) |_| {
            try self.writer.writeAll(codes.BOX_HORIZONTAL);
        }

        try self.writer.writeAll(codes.DIM);
        try self.writer.writeAll(help_text);
        try self.writer.writeAll(codes.DIM_END);

        const remaining = self.width -| help_len -| 2 -| (self.width -| help_len -| 2) / 2;
        for (0..remaining) |_| {
            try self.writer.writeAll(codes.BOX_HORIZONTAL);
        }

        try self.writer.writeAll(codes.BOX_BOTTOM_RIGHT);
        try self.writer.writeAll(codes.RESET);
    }

    pub fn positionCursorForInput(self: *Layout) !void {
        var buf: [32]u8 = undefined;
        const move_cmd = codes.moveTo(&buf, 2, 3);
        try self.writer.writeAll(move_cmd);
    }

    /// Clear and redraw only the query input line
    pub fn clearQueryLine(self: *Layout) !void {
        var buf: [32]u8 = undefined;
        const move_cmd = codes.moveTo(&buf, 2, 1);
        try self.writer.writeAll(move_cmd);

        try self.writer.writeAll(codes.CYAN);
        try self.writer.writeAll(codes.BOX_VERTICAL);
        try self.writer.writeAll(codes.RESET);

        for (0..self.width - 2) |_| {
            try self.writer.writeByte(' ');
        }

        try self.writer.writeAll(codes.CYAN);
        try self.writer.writeAll(codes.BOX_VERTICAL);
        try self.writer.writeAll(codes.RESET);

        try self.positionCursorForInput();
    }

    /// Get the maximum width available for query input
    pub fn queryInputWidth(self: *Layout) u16 {
        return self.width -| 4; // Account for borders and padding
    }

    /// Clear results area and position cursor for writing results
    pub fn clearResultsArea(self: *Layout) !void {
        for (0..self.results_height) |i| {
            var buf: [32]u8 = undefined;
            const row: u16 = @intCast(self.results_start_row + i);
            const move_cmd = codes.moveTo(&buf, row, 1);
            try self.writer.writeAll(move_cmd);

            try self.writer.writeAll(codes.CYAN);
            try self.writer.writeAll(codes.BOX_VERTICAL);
            try self.writer.writeAll(codes.RESET);

            for (0..self.width - 2) |_| {
                try self.writer.writeByte(' ');
            }

            try self.writer.writeAll(codes.CYAN);
            try self.writer.writeAll(codes.BOX_VERTICAL);
            try self.writer.writeAll(codes.RESET);
        }

        try self.positionCursorForResults();
    }

    /// Position cursor at start of results area
    pub fn positionCursorForResults(self: *Layout) !void {
        var buf: [32]u8 = undefined;
        const move_cmd = codes.moveTo(&buf, self.results_start_row, 3);
        try self.writer.writeAll(move_cmd);
    }

    /// Write a single result line at a specific row (0-indexed within results area)
    pub fn writeResultLine(self: *Layout, row: usize, content: []const u8, is_alternate: bool) !void {
        if (row >= self.results_height) return;

        var buf: [32]u8 = undefined;
        const actual_row: u16 = @intCast(self.results_start_row + row);
        const move_cmd = codes.moveTo(&buf, actual_row, 1);
        try self.writer.writeAll(move_cmd);

        try self.writer.writeAll(codes.CYAN);
        try self.writer.writeAll(codes.BOX_VERTICAL);
        try self.writer.writeAll(codes.RESET);

        if (is_alternate) {
            try self.writer.writeAll(codes.LIGHT_GREY_BG);
        }

        try self.writer.writeByte(' ');

        const max_content_len = self.width -| 4;
        const content_len = @min(content.len, max_content_len);
        try self.writer.writeAll(content[0..content_len]);

        // Pad remaining space
        const padding = max_content_len -| content_len;
        for (0..padding) |_| {
            try self.writer.writeByte(' ');
        }

        try self.writer.writeByte(' ');

        if (is_alternate) {
            try self.writer.writeAll(codes.RESET);
        }

        try self.writer.writeAll(codes.CYAN);
        try self.writer.writeAll(codes.BOX_VERTICAL);
        try self.writer.writeAll(codes.RESET);
    }

    /// Draw dropdown options overlaying results area
    pub fn drawDropdownOverlay(self: *Layout, options: []const []const u8, selected_index: u8, offset_col: u16) !void {
        const start_row = self.results_start_row;

        for (options, 0..) |option, i| {
            if (i >= self.results_height) break;

            var buf: [32]u8 = undefined;
            const row: u16 = @intCast(start_row + i);
            const move_cmd = codes.moveTo(&buf, row, offset_col);
            try self.writer.writeAll(move_cmd);

            if (i == selected_index) {
                try self.writer.writeAll(codes.HIGHLIGHT);
                try self.writer.writeAll(codes.BOX_T_RIGHT);
                try self.writer.writeByte(' ');
                try self.writer.writeAll(option);
                try self.writer.writeByte(' ');
                try self.writer.writeAll(codes.BOX_T_LEFT);
                try self.writer.writeAll(codes.RESET);
            } else {
                try self.writer.writeAll(codes.CYAN);
                try self.writer.writeAll(codes.BOX_VERTICAL);
                try self.writer.writeAll(codes.RESET);
                try self.writer.writeByte(' ');
                try self.writer.writeAll(option);
                try self.writer.writeByte(' ');
                try self.writer.writeAll(codes.CYAN);
                try self.writer.writeAll(codes.BOX_VERTICAL);
                try self.writer.writeAll(codes.RESET);
            }
        }

        // Draw dropdown border at bottom of options
        if (options.len < self.results_height) {
            var buf: [32]u8 = undefined;
            const row: u16 = @intCast(start_row + options.len);
            const move_cmd = codes.moveTo(&buf, row, offset_col);
            try self.writer.writeAll(move_cmd);

            try self.writer.writeAll(codes.CYAN);
            try self.writer.writeAll(codes.BOX_BOTTOM_LEFT);
            // Calculate dropdown width based on longest option
            var max_len: usize = 0;
            for (options) |opt| {
                if (opt.len > max_len) max_len = opt.len;
            }
            for (0..max_len + 2) |_| {
                try self.writer.writeAll(codes.BOX_HORIZONTAL);
            }
            try self.writer.writeAll(codes.BOX_BOTTOM_RIGHT);
            try self.writer.writeAll(codes.RESET);
        }
    }

    /// Write status/hint message in results area
    pub fn writeStatusMessage(self: *Layout, message: []const u8) !void {
        const row = self.results_height / 2;
        const col = (self.width -| @as(u16, @intCast(message.len))) / 2;

        var buf: [32]u8 = undefined;
        const actual_row: u16 = @intCast(self.results_start_row + row);
        const move_cmd = codes.moveTo(&buf, actual_row, col);
        try self.writer.writeAll(move_cmd);
        try self.writer.writeAll(codes.DIM);
        try self.writer.writeAll(message);
        try self.writer.writeAll(codes.DIM_END);
    }

    /// Write "more results" hint at bottom of results area
    pub fn writeMoreResultsHint(self: *Layout) !void {
        const row = self.results_height - 1;
        var buf: [32]u8 = undefined;
        const actual_row: u16 = @intCast(self.results_start_row + row);
        const move_cmd = codes.moveTo(&buf, actual_row, 3);
        try self.writer.writeAll(move_cmd);

        try self.writer.writeAll(codes.HIGHLIGHT);
        try self.writer.writeAll(codes.BOLD_START);
        try self.writer.writeAll("[n]");
        try self.writer.writeAll(codes.BOLD_END);
        try self.writer.writeAll(" more results | any key to dismiss");
        try self.writer.writeAll(codes.RESET);
    }

    /// Update mode indicator in top border
    pub fn updateModeIndicator(self: *Layout, mode: Mode) !void {
        const mode_str = switch (mode) {
            .tui => " [TUI] ",
            .raw => " [RAW] ",
        };
        const mode_len: u16 = @intCast(mode_str.len);
        const col = self.width - mode_len;

        var buf: [32]u8 = undefined;
        const move_cmd = codes.moveTo(&buf, 1, col);
        try self.writer.writeAll(move_cmd);

        try self.writer.writeAll(codes.YELLOW);
        try self.writer.writeAll(mode_str);
        try self.writer.writeAll(codes.CYAN);
        try self.writer.writeAll(codes.BOX_TOP_RIGHT);
        try self.writer.writeAll(codes.RESET);

        try self.positionCursorForInput();
    }
};

pub const Mode = enum {
    tui,
    raw,
};

fn terminalSize() ?TermSize {
    var ws: std.posix.winsize = undefined;
    const result = std.posix.system.ioctl(
        std.posix.STDOUT_FILENO,
        std.posix.T.IOCGWINSZ,
        @intFromPtr(&ws),
    );
    if (result == 0) {
        return TermSize{ .width = ws.col, .height = ws.row };
    }
    return null;
}
