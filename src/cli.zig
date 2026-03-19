const std = @import("std");
const codes = @import("codes.zig");

const delegate = @import("union_helpers.zig").delegate;
const delegateWithArg = @import("union_helpers.zig").delegateWithArg;
const Client = @import("client.zig").Client;
const TuiCli = @import("tui_cli.zig").TuiCli;
const RawCli = @import("raw_cli.zig").RawCli;

const INPUT_PREFIX = @import("constants.zig").INPUT_PREFIX;

pub const CliKind = enum(u8) { tui, raw };

pub const Cli = union(CliKind) {
    tui: TuiCli,
    raw: RawCli,

    pub fn init(allocator: std.mem.Allocator, client: *Client, writer: *std.Io.Writer) !Cli {
        return .{
            .tui = try TuiCli.init(allocator, client, writer),
        };
    }

    pub fn toggleMode(self: *Cli) !void {
        if (!self.canSwitchMode()) return;

        var allocator: std.mem.Allocator = undefined;
        var client: *Client = undefined;
        var writer: *std.Io.Writer = undefined;

        switch (self.*) {
            inline else => |*v| {
                allocator = v.allocator;
                client = v.client;
                writer = v.writer;
                v.deinit();
            },
        }

        self.* = switch (self.*) {
            .tui => .{ .raw = try RawCli.init(allocator, client, writer) },
            .raw => .{ .tui = try TuiCli.init(allocator, client, writer) },
        };

        try writer.writeAll("\r" ++ codes.ERASE_LINE ++ INPUT_PREFIX);
        if (self.* == .tui) {
            try self.tui.query_builder.render(INPUT_PREFIX.len, writer);
        }
    }

    fn canSwitchMode(self: *Cli) bool {
        return switch (self.*) {
            .tui => |*t| t.state == .empty,
            .raw => |*r| r.input_buffer.items.len == 0,
        };
    }

    pub const handleInput = delegateWithArg(Cli, "handleInput", u8, anyerror!void);
    pub const deinit = delegate(Cli, "deinit", void);
};
