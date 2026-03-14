const std = @import("std");
const codes = @import("codes.zig");

pub fn Dropdown(comptime num_options: u8, comptime title: []const u8, comptime options: [num_options][]const u8) type {
    return struct {
        const Self = @This();

        options: [num_options][]const u8 = options,
        selected_index: u8 = 0,
        title: []const u8 = title,

        pub fn select(self: *Self, index: u8) u8 {
            std.debug.assert(index < num_options);
            self.selected_index = index;
            return index;
        }

        pub fn render(self: *const Self, comptime offset: u32, writer: *std.Io.Writer) !void {
            try self.renderQueryKindSelector(writer, true);
            for (self.options, 0..) |option, i| {
                try writer.writeByte('\n');
                if (self.selected_index == i) {
                    try writer.print(
                        " " ** offset ++ "{s}>{s} {s}",
                        .{
                            codes.HIGHLIGHT,
                            option,
                            codes.RESET,
                        },
                    );
                } else {
                    try writer.print(" " ** offset ++ " {s}", .{option});
                }
            }
        }

        pub fn renderQueryKindSelector(self: *const Self, writer: *std.Io.Writer, is_active: bool) !void {
            if (is_active) {
                try writer.print(
                    "{s}{s} {s} {s}",
                    .{
                        codes.HIGHLIGHT,
                        codes.GREY,
                        self.title,
                        codes.RESET,
                    },
                );
            } else {
                try writer.print(
                    "{s} {s} {s}",
                    .{
                        codes.HIGHLIGHT,
                        self.title,
                        codes.RESET,
                    },
                );
            }
        }

        pub fn renderSelectedOption(self: *const Self, writer: *std.Io.Writer) !void {
            try writer.print(
                "{s}{s}{s} {s} {s} ",
                .{
                    codes.HIGHLIGHT,
                    codes.GREY,
                    codes.BOLD_START,
                    self.selected(),
                    codes.RESET,
                },
            );
        }

        pub inline fn selected(self: *const Self) []const u8 {
            return self.options[self.selected_index];
        }
    };
}
