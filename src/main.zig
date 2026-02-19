const std = @import("std");
const codes = @import("codes.zig");

const Cli = @import("cli.zig").Cli;
const Client = @import("client.zig").Client;
const Keys = @import("constants.zig").Keys;

const INPUT_PREFIX = @import("constants.zig").INPUT_PREFIX;

fn switchToRawMode(fd: *const std.fs.File) !std.posix.termios {
    var raw = try std.posix.tcgetattr(fd.handle);
    const orig = raw;

    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
    try std.posix.tcsetattr(fd.handle, .NOW, raw);

    return orig;
}

fn createScreen(fd: *const std.fs.File) !void {
    try fd.writeAll(codes.NEW_SCREEN);
}

fn restoreScreen(fd: *const std.fs.File) !void {
    try fd.writeAll(codes.EXIT_SCREEN);
}

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    var stdin = std.fs.File.stdin();
    var stdout = std.fs.File.stdout();

    var client = Client.init(allocator, [4]u8{ 127, 0, 0, 1 }, 7733) catch {
        try stdout.writeAll("Failed to initialize client\n");
        return;
    };
    defer client.deinit();
    client.connect() catch {
        try stdout.writeAll("Failed to connect to server\n");
        return;
    };

    const orig = try switchToRawMode(&stdin);
    defer std.posix.tcsetattr(stdin.handle, .NOW, orig) catch {};

    try createScreen(&stdout);
    defer restoreScreen(&stdout) catch {};

    var writer = stdout.writer(&[0]u8{});

    var cli_instance: Cli = try Cli.init(allocator, &client, &writer.interface);
    defer cli_instance.deinit();

    try writer.interface.writeAll(INPUT_PREFIX);
    try cli_instance.tui.query_builder.render(INPUT_PREFIX.len, &writer.interface);

    var buf: [1]u8 = undefined;
    while (true) {
        const n = try stdin.read(&buf);
        if (n == 0 or buf[0] == Keys.CTRL_C) break;
        if (buf[0] == Keys.CTRL_T) {
            try cli_instance.toggleMode();
            continue;
        }
        try cli_instance.handleInput(buf[0]);
    }
}
