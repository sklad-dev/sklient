const std = @import("std");
const codes = @import("codes.zig");

const Client = @import("client.zig").Client;
const Keys = @import("constants.zig").Keys;
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
        self.request_buffer.deinit(self.allocator);
        self.input_buffer.deinit(self.allocator);
    }

    pub fn nextState(self: *RawCli) anyerror!void {
        switch (self.state) {
            .userInput => {
                self.state = .executing;
                try self.executeQuery();
            },
            .executing => {
                self.input_buffer.clearRetainingCapacity();
                self.state = .userInput;
            },
            .awaitingContinue => self.state = .userInput,
        }
    }

    pub fn handleInput(self: *RawCli, key: u8) !void {
        return switch (self.state) {
            .userInput => try self.handleUserInput(key),
            else => {},
        };
    }

    pub fn executeQuery(self: *RawCli) !void {
        const req = Request{
            .kind = .query,
            .query = self.input_buffer.items,
            .timestamp = std.time.microTimestamp(),
        };

        var json_writer = std.Io.Writer.Allocating.init(self.allocator);
        defer json_writer.deinit();
        try req.toString(&json_writer.writer);

        const response = try self.client.send(try json_writer.toOwnedSlice());
        try self.writer.writeByte('\n');
        try self.writer.writeAll(response);
        try self.writer.writeByte('\n');

        try self.nextState();
    }

    fn handleUserInput(self: *RawCli, key: u8) !void {
        if (key == Keys.ENTER) {
            try self.nextState();
        } else if (key == Keys.BACKSPACE) {
            _ = self.input_buffer.pop();
        } else {
            try self.input_buffer.append(self.allocator, key);
        }
        try self.renderPrompt();
    }

    fn renderPrompt(self: *RawCli) !void {
        try self.writer.writeAll("\r" ++ codes.ERASE_LINE);
        try self.writer.writeAll(INPUT_PREFIX);
        try self.writer.writeAll(self.input_buffer.items);
    }
};
