const std = @import("std");
const codes = @import("codes.zig");

const Client = @import("client.zig").Client;
const Keys = @import("constants.zig").Keys;
const Response = @import("response.zig").Response;
const Request = @import("request.zig").Request;
const RequestKind = @import("request.zig").RequestKind;

const INPUT_PREFIX = @import("constants.zig").INPUT_PREFIX;

pub const RawCli = struct {
    allocator: std.mem.Allocator,
    state: State,
    input_buffer: std.ArrayList(u8),
    request_buffer: std.ArrayList(u8),
    client: *Client,
    writer: *std.Io.Writer,
    has_more_results: bool = false,

    const State = enum(u8) {
        userInput,
        executing,
        awaitingContinue,
    };

    pub fn init(allocator: std.mem.Allocator, client: *Client, writer: *std.Io.Writer) !RawCli {
        return .{
            .allocator = allocator,
            .state = .userInput,
            .input_buffer = try std.ArrayList(u8).initCapacity(allocator, 256),
            .request_buffer = try std.ArrayList(u8).initCapacity(allocator, 1024),
            .client = client,
            .writer = writer,
        };
    }

    pub fn deinit(self: *RawCli) void {
        self.input_buffer.deinit(self.allocator);
    }

    pub fn nextState(self: *RawCli) anyerror!void {
        switch (self.state) {
            .userInput => {
                self.state = .executing;
                try self.executeQuery();
            },
            .executing, .awaitingContinue => {
                self.input_buffer.clearRetainingCapacity();
                if (!self.has_more_results) {
                    self.state = .userInput;
                } else {
                    self.state = .awaitingContinue;
                }
            },
        }
    }

    pub fn handleInput(self: *RawCli, key: u8) !void {
        return switch (self.state) {
            .userInput => try self.handleUserInput(key),
            .awaitingContinue => try self.handleAwaitingContinue(key),
            else => {},
        };
    }

    pub fn executeQuery(self: *RawCli) !void {
        try self.sendRequest(.{
            .kind = .query,
            .query = self.input_buffer.items,
            .timestamp = std.time.microTimestamp(),
        });
    }

    fn sendRequest(self: *RawCli, req: Request) !void {
        var json_writer = std.Io.Writer.Allocating.init(self.allocator);
        defer json_writer.deinit();
        try req.toString(&json_writer.writer);

        const request_bytes = try json_writer.toOwnedSlice();
        defer self.allocator.free(request_bytes);
        const response_bytes = try self.client.send(request_bytes);
        const response = try std.json.parseFromSlice(Response, self.allocator, response_bytes, .{});
        defer response.deinit();

        self.has_more_results = switch (response.value.data) {
            .array => |arr| arr.items.len > 0,
            else => false,
        };
        try self.writer.writeByte('\n');
        try response.value.render(self.writer, self.has_more_results);

        try self.nextState();
        if (!self.has_more_results) {
            switch (response.value.data) {
                .array => try self.renderPrompt(),
                else => {},
            }
        }
    }

    fn executeContinueBatch(self: *RawCli) !void {
        try self.writer.writeAll("\r" ++ codes.ERASE_LINE);
        try self.sendRequest(.{
            .kind = .continue_batch,
            .query = &[_]u8{},
            .timestamp = std.time.microTimestamp(),
        });
    }

    fn handleUserInput(self: *RawCli, key: u8) !void {
        if (key == Keys.ENTER) {
            try self.nextState();
        } else if (key == Keys.BACKSPACE) {
            _ = self.input_buffer.pop();
        } else {
            try self.input_buffer.append(self.allocator, key);
        }

        if (self.state != .awaitingContinue) {
            try self.renderPrompt();
        }
    }

    fn handleAwaitingContinue(self: *RawCli, key: u8) !void {
        if (key == 'n' or key == 'N') {
            try self.executeContinueBatch();
        } else {
            self.has_more_results = false;
            try self.nextState();
            try self.renderPrompt();
        }
    }

    fn renderPrompt(self: *RawCli) !void {
        try self.writer.writeAll("\r" ++ codes.ERASE_LINE);
        try self.writer.writeAll(INPUT_PREFIX);
        try self.writer.writeAll(self.input_buffer.items);
    }
};
