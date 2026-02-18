const std = @import("std");
const input_field = @import("input_field.zig");
const dropdown = @import("dropdown.zig");
const cli = @import("cli.zig");
const codes = @import("codes.zig");
const request = @import("request.zig");

const Client = @import("client.zig").Client;

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

    var cli_instance = try cli.Cli.init(allocator);
    defer cli_instance.deinit();

    var stdin = std.fs.File.stdin();
    var stdout = std.fs.File.stdout();

    const orig = try switchToRawMode(&stdin);
    defer std.posix.tcsetattr(stdin.handle, .NOW, orig) catch {};

    try createScreen(&stdout);
    defer restoreScreen(&stdout) catch {};

    var buf: [1]u8 = undefined;
    var writer = stdout.writer(&[0]u8{});

    try writer.interface.writeAll(cli.INPUT_PREFIX);
    try cli_instance.query_builder.render(cli.INPUT_PREFIX.len, &writer.interface);

    var client = try Client.init(allocator, [4]u8{ 127, 0, 0, 1 }, 7733);
    defer client.deinit();
    try client.connect();

    while (true) {
        const n = try stdin.read(&buf);
        if (n == 0) break;

        const key = buf[0];

        if (key == 3) break;

        switch (cli_instance.state) {
            .empty => {
                if (key == ' ') {
                    try cli_instance.nextState();
                    try writer.interface.writeAll(codes.CLEAR_SCREEN ++ cli.INPUT_PREFIX);
                    try cli_instance.query_builder.render(cli.INPUT_PREFIX.len, &writer.interface);
                }
            },
            .selectingQueryKind => {
                const options_num: u8 = @intCast(cli_instance.query_builder.query_kind_dropdown.?.options.len);
                if (key == 66) {
                    cli_instance.query_builder.query_kind_dropdown.?.selected_index = (cli_instance.query_builder.query_kind_dropdown.?.selected_index + 1) % options_num;
                } else if (key == 65) {
                    if (cli_instance.query_builder.query_kind_dropdown.?.selected_index == 0) {
                        cli_instance.query_builder.query_kind_dropdown.?.selected_index = options_num - 1;
                    } else {
                        cli_instance.query_builder.query_kind_dropdown.?.selected_index = cli_instance.query_builder.query_kind_dropdown.?.selected_index - 1;
                    }
                } else if (key == 10) {
                    try cli_instance.nextState();

                    try writer.interface.writeAll(codes.CLEAR_SCREEN ++ cli.INPUT_PREFIX);
                    try cli_instance.query_builder.render(cli.INPUT_PREFIX.len, &writer.interface);

                    continue;
                } else {
                    continue;
                }

                try writer.interface.writeAll(codes.CLEAR_SCREEN ++ cli.INPUT_PREFIX);
                try cli_instance.query_builder.render(cli.INPUT_PREFIX.len, &writer.interface);
            },
            .providingParameters => {
                if (key == 10) {
                    try cli_instance.nextState();
                } else {
                    if (key == 127) {
                        _ = (try cli_instance.query_builder.activeBuffer()).?.pop();
                    } else {
                        try (try cli_instance.query_builder.activeBuffer()).?.append(cli_instance.query_builder.allocator, key);
                    }
                }
                try writer.interface.writeAll(codes.CLEAR_SCREEN ++ cli.INPUT_PREFIX);
                try cli_instance.query_builder.render(cli.INPUT_PREFIX.len, &writer.interface);
            },
            .executing => {
                try cli_instance.query_builder.generateQueryString(
                    cli_instance.allocator,
                    &cli_instance.request_buffer,
                );

                var json_writer = std.Io.Writer.Allocating.init(allocator);
                defer json_writer.deinit();

                const req = request.Request{
                    .kind = .query,
                    .query = cli_instance.request_buffer.items,
                    .timestamp = std.time.microTimestamp(),
                };
                try req.toString(&json_writer.writer);

                const response = try client.send(try json_writer.toOwnedSlice());

                try writer.interface.writeByte('\n');
                try writer.interface.writeAll(response);

                try cli_instance.nextState();

                try writer.interface.writeAll("\n" ++ cli.INPUT_PREFIX);
                try cli_instance.query_builder.render(cli.INPUT_PREFIX.len, &writer.interface);
            },
            else => break,
        }
    }
}
