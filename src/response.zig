const std = @import("std");
const codes = @import("codes.zig");

pub const Response = struct {
    data: std.json.Value,
    errors: ?[]const u8,

    pub fn render(self: *const Response, writer: *std.Io.Writer) !void {
        try writer.writeByte('\n');
        switch (self.data) {
            .null => {
                try renderValuePrefix(writer);
                try writer.writeAll("null");
            },
            .string => |s| {
                try renderValuePrefix(writer);
                try writer.writeAll(s);
            },
            .integer => |i| {
                try renderValuePrefix(writer);
                try writer.print("{d}", .{i});
            },
            .float => |f| {
                try renderValuePrefix(writer);
                try writer.print("{d}", .{f});
            },
            .array => {
                const table_view = ResponseTable.init(self);
                try table_view.render(writer);
            },
            else => {},
        }
        try writer.writeByte('\n');
    }

    fn renderValuePrefix(writer: *std.Io.Writer) !void {
        try writer.print(
            "{s}{s}{s}: ",
            .{
                codes.GREY,
                "value",
                codes.RESET,
            },
        );
    }
};

pub const ResponseTable = struct {
    const KEY_COLUMN = "keys";
    const VALUE_COLUMN = "values";

    response: *const Response,

    pub fn init(response: *const Response) ResponseTable {
        return .{ .response = response };
    }

    pub fn render(self: *const ResponseTable, writer: *std.Io.Writer) !void {
        _ = self;
        try writer.print(
            "{s} {s} {s}",
            .{
                codes.HIGHLIGHT,
                "RESULT STUB",
                codes.RESET,
            },
        );
    }

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
};
