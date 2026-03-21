const std = @import("std");
const codes = @import("codes.zig");

const Cli = @import("cli.zig").Cli;
const Client = @import("client.zig").Client;
const Keys = @import("constants.zig").Keys;
const Layout = @import("layout.zig").Layout;
const History = @import("history.zig").History;
const Mode = @import("layout.zig").Mode;

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

    // Initialize layout and history
    var layout = Layout.init(&writer.interface);
    var history = History.init(allocator);
    defer history.deinit();

    // Draw initial frame
    try layout.drawFrame(.tui);

    var cli_instance: Cli = try Cli.init(allocator, &client, &writer.interface, &layout, &history);
    defer cli_instance.deinit();

    // Render initial TUI prompt
    try cli_instance.tui.query_builder.render(INPUT_PREFIX.len, &writer.interface);

    // Escape sequence buffer for multi-byte key sequences
    var escape_buf: [3]u8 = undefined;
    var escape_len: usize = 0;
    var in_escape: bool = false;

    var buf: [1]u8 = undefined;
    while (true) {
        const n = try stdin.read(&buf);
        if (n == 0) break;

        const key = buf[0];

        // Handle escape sequences (arrow keys)
        if (key == 27) { // ESC
            in_escape = true;
            escape_len = 0;
            continue;
        }

        if (in_escape) {
            escape_buf[escape_len] = key;
            escape_len += 1;

            if (escape_len == 2 and escape_buf[0] == '[') {
                // Complete arrow key sequence
                in_escape = false;
                const arrow_key = escape_buf[1];
                try cli_instance.handleInput(arrow_key);
                continue;
            }

            if (escape_len >= 3) {
                // Unknown escape sequence, ignore
                in_escape = false;
            }
            continue;
        }

        if (key == Keys.CTRL_C) break;

        if (key == Keys.CTRL_T) {
            try cli_instance.toggleMode();
            continue;
        }

        try cli_instance.handleInput(key);
    }
}
