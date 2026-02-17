const std = @import("std");
const codes = @import("codes.zig");

pub const InputField = struct {
    allocator: std.mem.Allocator,
    label: []const u8,
    buffer: *std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, label: []const u8, buffer: *std.ArrayList(u8)) !InputField {
        return InputField{
            .allocator = allocator,
            .label = label,
            .buffer = buffer,
        };
    }

    pub fn render(self: *const InputField, writer: *std.Io.Writer) !void {
        try writer.print(
            "{s} {s} {s}:{s}",
            .{
                codes.HIGHLIGHT,
                self.label,
                codes.RESET,
                codes.UNDERLINE_START,
            },
        );
        try writer.writeAll(self.buffer.items);
        try writer.writeAll(codes.UNDERLINE_END);
    }
};
