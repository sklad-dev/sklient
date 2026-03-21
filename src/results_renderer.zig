const std = @import("std");
const codes = @import("codes.zig");
const Layout = @import("layout.zig").Layout;

/// Renders query results within the TUI layout with alternating row colors.
pub const ResultsRenderer = struct {
    layout: *Layout,
    allocator: std.mem.Allocator,

    const SEPARATOR = "  ";
    const MIN_COL_WIDTH = 5;
    const ELLIPSIS = "...";

    pub fn init(allocator: std.mem.Allocator, layout: *Layout) ResultsRenderer {
        return .{
            .layout = layout,
            .allocator = allocator,
        };
    }

    /// Render a single scalar value (null, string, integer, float)
    pub fn renderScalar(self: *ResultsRenderer, value: std.json.Value) !void {
        try self.layout.clearResultsArea();

        var buf: [256]u8 = undefined;
        const str = formatValue(&buf, value);

        try self.layout.writeResultLine(0, str, false);
        try self.layout.positionCursorForInput();
    }

    /// Render an array of key-value pairs with alternating row colors
    pub fn renderKeyValuePairs(self: *ResultsRenderer, items: []const std.json.Value, show_more_hint: bool) !void {
        try self.layout.clearResultsArea();

        if (items.len == 0) {
            try self.layout.writeStatusMessage("No results");
            try self.layout.positionCursorForInput();
            return;
        }

        // Calculate column widths
        const col_info = calculateColumnWidths(items, self.layout.queryInputWidth());

        // Render each row
        const max_rows = if (show_more_hint)
            self.layout.results_height - 1
        else
            self.layout.results_height;

        var row_idx: usize = 0;
        for (items) |item| {
            if (row_idx >= max_rows) break;
            if (item != .object) continue;

            const key = item.object.get("key") orelse continue;
            const val = item.object.get("value") orelse std.json.Value{ .null = {} };

            var line_buf: [512]u8 = undefined;
            const line = formatKeyValueLine(&line_buf, key, val, col_info.key_width, col_info.val_width);

            try self.layout.writeResultLine(row_idx, line, row_idx % 2 == 1);
            row_idx += 1;
        }

        if (show_more_hint) {
            try self.layout.writeMoreResultsHint();
        }

        try self.layout.positionCursorForInput();
    }

    /// Render an error message
    pub fn renderError(self: *ResultsRenderer, error_msg: []const u8) !void {
        try self.layout.clearResultsArea();

        var buf: [512]u8 = undefined;
        const len = @min(error_msg.len, buf.len - 10);
        const msg = std.fmt.bufPrint(&buf, "Error: {s}", .{error_msg[0..len]}) catch "Error";

        try self.layout.writeResultLine(0, msg, false);
        try self.layout.positionCursorForInput();
    }

    /// Clear the results area
    pub fn clear(self: *ResultsRenderer) !void {
        try self.layout.clearResultsArea();
        try self.layout.positionCursorForInput();
    }

    /// Show a status message centered in results area
    pub fn showMessage(self: *ResultsRenderer, message: []const u8) !void {
        try self.layout.clearResultsArea();
        try self.layout.writeStatusMessage(message);
        try self.layout.positionCursorForInput();
    }
};

const ColumnInfo = struct {
    key_width: usize,
    val_width: usize,
};

fn calculateColumnWidths(items: []const std.json.Value, available_width: u16) ColumnInfo {
    var max_key_len: usize = 0;
    var max_val_len: usize = 0;

    for (items) |item| {
        if (item != .object) continue;

        if (item.object.get("key")) |key| {
            const len = valueLength(key);
            if (len > max_key_len) max_key_len = len;
        }
        if (item.object.get("value")) |val| {
            const len = valueLength(val);
            if (len > max_val_len) max_val_len = len;
        }
    }

    const available: usize = @as(usize, available_width) -| ResultsRenderer.SEPARATOR.len;
    var key_width = max_key_len;
    var val_width = max_val_len;

    if (key_width + val_width > available) {
        const total = key_width + val_width;
        key_width = @max(ResultsRenderer.MIN_COL_WIDTH, (available * max_key_len) / total);
        val_width = @max(ResultsRenderer.MIN_COL_WIDTH, available -| key_width);
    }

    return .{ .key_width = key_width, .val_width = val_width };
}

fn formatKeyValueLine(buf: []u8, key: std.json.Value, val: std.json.Value, key_width: usize, val_width: usize) []const u8 {
    var key_buf: [256]u8 = undefined;
    var val_buf: [256]u8 = undefined;

    const key_str = formatValue(&key_buf, key);
    const val_str = formatValue(&val_buf, val);

    var pos: usize = 0;

    // Write key (potentially truncated)
    const key_len = @min(key_str.len, key_width);
    if (key_len < key_width and key_str.len <= key_width) {
        @memcpy(buf[pos .. pos + key_len], key_str[0..key_len]);
        pos += key_len;
        // Pad
        const pad = key_width - key_len;
        @memset(buf[pos .. pos + pad], ' ');
        pos += pad;
    } else if (key_str.len > key_width) {
        // Truncate with ellipsis
        const trunc = key_width -| 3;
        @memcpy(buf[pos .. pos + trunc], key_str[0..trunc]);
        pos += trunc;
        @memcpy(buf[pos .. pos + 3], "...");
        pos += 3;
    } else {
        @memcpy(buf[pos .. pos + key_len], key_str[0..key_len]);
        pos += key_len;
        const pad = key_width - key_len;
        @memset(buf[pos .. pos + pad], ' ');
        pos += pad;
    }

    // Write separator
    @memcpy(buf[pos .. pos + ResultsRenderer.SEPARATOR.len], ResultsRenderer.SEPARATOR);
    pos += ResultsRenderer.SEPARATOR.len;

    // Write value (potentially truncated)
    const val_len = @min(val_str.len, val_width);
    if (val_str.len <= val_width) {
        @memcpy(buf[pos .. pos + val_len], val_str[0..val_len]);
        pos += val_len;
    } else {
        // Truncate with ellipsis
        const trunc = val_width -| 3;
        @memcpy(buf[pos .. pos + trunc], val_str[0..trunc]);
        pos += trunc;
        @memcpy(buf[pos .. pos + 3], "...");
        pos += 3;
    }

    return buf[0..pos];
}

fn formatValue(buf: []u8, value: std.json.Value) []const u8 {
    return switch (value) {
        .null => "null",
        .bool => |b| if (b) "true" else "false",
        .integer => |i| std.fmt.bufPrint(buf, "{d}", .{i}) catch "?",
        .float => |f| std.fmt.bufPrint(buf, "{d}", .{f}) catch "?",
        .string => |s| blk: {
            if (s.len + 2 <= buf.len) {
                buf[0] = '\'';
                @memcpy(buf[1 .. 1 + s.len], s);
                buf[1 + s.len] = '\'';
                break :blk buf[0 .. s.len + 2];
            }
            break :blk s;
        },
        .number_string => |s| s,
        else => "?",
    };
}

fn valueLength(value: std.json.Value) usize {
    return switch (value) {
        .null => 4,
        .bool => |b| if (b) 4 else 5,
        .integer, .float => {
            var buf: [256]u8 = undefined;
            return formatValue(&buf, value).len;
        },
        .number_string => |s| s.len,
        .string => |s| s.len + 2, // Account for quotes
        else => 1,
    };
}
