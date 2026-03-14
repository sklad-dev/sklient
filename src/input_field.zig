const std = @import("std");
const codes = @import("codes.zig");

pub const InputField = struct {
    label: []const u8,
    buffer: *std.ArrayList(u8),

    pub fn init(label: []const u8, buffer: *std.ArrayList(u8)) InputField {
        return .{ .label = label, .buffer = buffer };
    }

    pub fn render(self: *const InputField, writer: *std.Io.Writer, is_active: bool) !void {
        if (is_active) {
            try writer.print(
                "{s} {s} {s}:{s}",
                .{
                    codes.HIGHLIGHT,
                    self.label,
                    codes.RESET,
                    codes.UNDERLINE_START,
                },
            );
        } else {
            try writer.print(
                "{s}{s} {s} {s}:{s}",
                .{
                    codes.HIGHLIGHT,
                    codes.GREY,
                    self.label,
                    codes.RESET,
                    codes.UNDERLINE_START,
                },
            );
        }
        try writer.writeAll(self.buffer.items);
        try writer.writeAll(codes.UNDERLINE_END);
    }
};
