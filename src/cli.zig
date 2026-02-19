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
        if (self.canSwitchMode()) {
            switch (self.*) {
                .tui => |*t| {
                    const allocator = t.allocator;
                    const client = t.client;
                    const writer = t.writer;
                    t.deinit();

                    self.* = .{ .raw = try RawCli.init(allocator, client, writer) };

                    try writer.writeAll("\r" ++ codes.ERASE_LINE ++ INPUT_PREFIX);
                },
                .raw => |*r| {
                    const allocator = r.allocator;
                    const client = r.client;
                    const writer = r.writer;
                    r.deinit();

                    self.* = .{ .tui = try TuiCli.init(allocator, client, writer) };

                    try writer.writeAll("\r" ++ codes.ERASE_LINE ++ INPUT_PREFIX);
                    try self.tui.query_builder.render(INPUT_PREFIX.len, writer);
                },
            }
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
