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
            try self.renderQueryKindSelector(writer);
            for (self.options, 0..) |option, i| {
                if (self.selected_index == i) {
                    try writer.print(
                        " " ** offset ++ "{s}>{s} {s}\n",
                        .{
                            codes.HIGHLIGHT,
                            option,
                            codes.RESET,
                        },
                    );
                } else {
                    try writer.print(" " ** offset ++ " {s}\n", .{option});
                }
            }
        }

        pub fn renderQueryKindSelector(self: *const Self, writer: *std.Io.Writer) !void {
            try writer.print(
                "{s}{s} {s} {s}\n",
                .{
                    codes.HIGHLIGHT,
                    codes.GREY,
                    self.title,
                    codes.RESET,
                },
            );
        }

        pub fn renderSelectedOption(self: *const Self, writer: *std.Io.Writer) !void {
            try writer.print(
                "{s}{s} {s} {s} ",
                .{
                    codes.HIGHLIGHT,
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
