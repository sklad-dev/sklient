const std = @import("std");
const codes = @import("codes.zig");

pub const Response = struct {
    data: std.json.Value,
    errors: ?[]const u8,

    pub fn render(self: *const Response, writer: *std.Io.Writer) !void {
        try writer.writeByte('\n');
        switch (self.data) {
            .null => try writer.writeAll("null"),
            .string => |s| try writer.print("'{s}'", .{s}),
            .integer => |i| try writer.print("{d}", .{i}),
            .float => |f| try writer.print("{d}", .{f}),
            .array => |arr| {
                if (arr.items.len == 0) {
                    try writer.writeAll("null");
                } else {
                    const table_view = ResponseTable.init(arr.items);
                    try table_view.render(writer);
                }
            },
            else => {},
        }
        try writer.writeByte('\n');
    }
};

const ResponseTable = struct {
    items: []const std.json.Value,
    term_width: u16,
    max_key_len: usize,
    max_val_len: usize,
    key_col_width: usize,
    val_col_width: usize,

    const SEPARATOR = "  ";
    const MIN_COL_WIDTH = 5;
    const ELLIPSIS = "...";

    pub fn init(items: []const std.json.Value) ResponseTable {
        const term_width: u16 = if (terminalSize()) |size| size.width else 80;

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

        const available = @as(usize, term_width) -| SEPARATOR.len;
        var key_col_width = max_key_len;
        var val_col_width = max_val_len;

        if (key_col_width + val_col_width > available) {
            const total = key_col_width + val_col_width;
            key_col_width = @max(MIN_COL_WIDTH, (available * max_key_len) / total);
            val_col_width = @max(MIN_COL_WIDTH, available -| key_col_width);
        }

        return .{
            .items = items,
            .term_width = term_width,
            .max_key_len = max_key_len,
            .max_val_len = max_val_len,
            .key_col_width = key_col_width,
            .val_col_width = val_col_width,
        };
    }

    pub fn render(self: *const ResponseTable, writer: *std.Io.Writer) !void {
        for (self.items, 0..) |item, i| {
            if (item != .object) continue;

            const key = item.object.get("key") orelse continue;
            const val = item.object.get("value") orelse std.json.Value{ .null = {} };

            try self.writeValue(writer, key, self.key_col_width);
            try writer.writeAll(SEPARATOR);
            try self.writeValue(writer, val, self.val_col_width);
            if (i != self.items.len - 1) try writer.writeByte('\n');
        }
    }

    fn writeValue(self: *const ResponseTable, writer: *std.Io.Writer, value: std.json.Value, max_width: usize) !void {
        _ = self;
        var buf: [256]u8 = undefined;
        const length = valueLength(value);
        const str = valueToString(&buf, value);

        if (length <= max_width) {
            if (length == str.len + 2) try writer.writeByte('\'');
            try writer.writeAll(str);
            if (length == str.len + 2) try writer.writeByte('\'');
            for (0..max_width - str.len) |_| {
                try writer.writeByte(' ');
            }
        } else {
            const truncate_at = max_width -| ELLIPSIS.len;
            try writer.writeAll(str[0..truncate_at]);
            try writer.writeAll(ELLIPSIS);
        }
    }

    fn valueLength(value: std.json.Value) u64 {
        return switch (value) {
            .null => 4,
            .bool => |b| if (b) 4 else 5,
            .integer, .float => {
                var buf: [256]u8 = undefined;
                return valueToString(&buf, value).len;
            },
            .number_string => |s| s.len,
            .string => |s| s.len + 2,
            else => 1,
        };
    }

    fn valueToString(buf: []u8, value: std.json.Value) []const u8 {
        return switch (value) {
            .null => "null",
            .bool => |b| if (b) "true" else "false",
            .integer => |i| std.fmt.bufPrint(buf, "{d}", .{i}) catch "?",
            .float => |f| std.fmt.bufPrint(buf, "{d}", .{f}) catch "?",
            .string, .number_string => |s| s,
            else => "?",
        };
    }
};

fn terminalSize() ?struct { width: u16, height: u16 } {
    var ws: std.posix.winsize = undefined;
    const result = std.posix.system.ioctl(
        std.posix.STDOUT_FILENO,
        std.posix.T.IOCGWINSZ,
        @intFromPtr(&ws),
    );
    if (result == 0) {
        return .{ .width = ws.col, .height = ws.row };
    }
    return null;
}
