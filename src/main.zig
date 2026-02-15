const std = @import("std");
const dropdown = @import("dropdown.zig");
const cli = @import("cli.zig");
const codes = @import("codes.zig");

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

const QueryKindDropdown = dropdown.Dropdown(
    3,
    "query",
    [_][]const u8{
        "set",
        "get",
        "delete",
    },
);

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    var cli_instance = try cli.Cli.init(allocator);
    defer cli_instance.deinit();

    var stdin = std.fs.File.stdin();
    var stdout = std.fs.File.stdout();

    const orig = try switchToRawMode(&stdin);
    defer std.posix.tcsetattr(stdin.handle, .NOW, orig) catch {};

    try createScreen(&stdout);
    defer restoreScreen(&stdout) catch {};

    var query_kind_dropdown = QueryKindDropdown{};

    var buf: [1]u8 = undefined;
    var writer = stdout.writer(&[0]u8{});
    try writer.interface.writeAll(cli.INPUT_PREFIX);
    try query_kind_dropdown.renderQueryKindSelector(&writer.interface);

    while (true) {
        const n = try stdin.read(&buf);
        if (n == 0) break;

        const key = buf[0];

        if (key == 'q' or key == 3) break;

        switch (cli_instance.state) {
            .empty => {
                if (key == ' ') {
                    cli_instance.nextState();
                    try stdout.writeAll(codes.CLEAR_SCREEN);
                    try writer.interface.writeAll(cli.INPUT_PREFIX);
                    try query_kind_dropdown.render(cli.INPUT_PREFIX.len, &writer.interface);
                }
            },
            .selectingQueryKind => {
                if (key == 66) {
                    query_kind_dropdown.selected_index = (query_kind_dropdown.selected_index + 1) % 3;
                } else if (key == 65) {
                    if (query_kind_dropdown.selected_index == 0) {
                        query_kind_dropdown.selected_index = 2;
                    } else {
                        query_kind_dropdown.selected_index = query_kind_dropdown.selected_index - 1;
                    }
                } else if (key == 10) {
                    cli_instance.nextState();

                    try stdout.writeAll(codes.CLEAR_SCREEN);
                    try writer.interface.writeAll(cli.INPUT_PREFIX);
                    try query_kind_dropdown.renderSelectedOption(&writer.interface);
                    try writer.interface.writeAll(" ");

                    continue;
                } else {
                    continue;
                }

                try stdout.writeAll(codes.CLEAR_SCREEN);
                try writer.interface.writeAll(cli.INPUT_PREFIX);
                try query_kind_dropdown.render(cli.INPUT_PREFIX.len, &writer.interface);
            },
            else => break,
        }
    }

    try stdout.writeAll("\n");
}
