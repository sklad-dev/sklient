const std = @import("std");
const codes = @import("codes.zig");

const delegate = @import("union_helpers.zig").delegate;
const delegateWithArg = @import("union_helpers.zig").delegateWithArg;
const Client = @import("client.zig").Client;
const TuiCli = @import("tui_cli.zig").TuiCli;
const RawCli = @import("raw_cli.zig").RawCli;
const Layout = @import("layout.zig").Layout;
const History = @import("history.zig").History;
const Mode = @import("layout.zig").Mode;

const INPUT_PREFIX = @import("constants.zig").INPUT_PREFIX;

pub const CliKind = enum(u8) { tui, raw };

pub const Cli = union(CliKind) {
    tui: TuiCli,
    raw: RawCli,

    pub fn init(
        allocator: std.mem.Allocator,
        client: *Client,
        writer: *std.Io.Writer,
        layout: *Layout,
        history: *History,
    ) !Cli {
        return .{
            .tui = try TuiCli.init(allocator, client, writer, layout, history),
        };
    }

    pub fn toggleMode(self: *Cli) !void {
        if (!self.canSwitchMode()) return;

        var allocator: std.mem.Allocator = undefined;
        var client: *Client = undefined;
        var writer: *std.Io.Writer = undefined;
        var layout: *Layout = undefined;
        var history: *History = undefined;

        switch (self.*) {
            inline else => |*v| {
                allocator = v.allocator;
                client = v.client;
                writer = v.writer;
                layout = v.layout;
                history = v.history;
                v.deinit();
            },
        }

        self.* = switch (self.*) {
            .tui => .{ .raw = try RawCli.init(allocator, client, writer, layout, history) },
            .raw => .{ .tui = try TuiCli.init(allocator, client, writer, layout, history) },
        };

        // Update mode indicator and render initial prompt
        const mode: Mode = switch (self.*) {
            .tui => .tui,
            .raw => .raw,
        };
        try layout.updateModeIndicator(mode);

        switch (self.*) {
            .tui => |*t| try t.renderInitial(),
            .raw => |*r| try r.renderInitial(),
        }
    }

    pub fn currentMode(self: *Cli) Mode {
        return switch (self.*) {
            .tui => .tui,
            .raw => .raw,
        };
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
