const std = @import("std");
const codes = @import("codes.zig");

const Client = @import("client.zig").Client;
const Executor = @import("request.zig").Executor;
const Key = @import("constants.zig").Key;
const Keys = @import("constants.zig").Keys;
const Response = @import("response.zig").Response;
const Request = @import("request.zig").Request;
const RequestKind = @import("request.zig").RequestKind;

const INPUT_PREFIX = @import("constants.zig").INPUT_PREFIX;

pub const RawCli = struct {
    allocator: std.mem.Allocator,
    state: State,
    executor: Executor,
    input_buffer: std.ArrayList(u8),
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
            .executor = Executor.init(allocator, client),
            .input_buffer = try std.ArrayList(u8).initCapacity(allocator, 256),
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
                try self.executor.sendRequest(
                    RawCli,
                    .{
                        .kind = .query,
                        .query = self.input_buffer.items,
                        .timestamp = std.time.microTimestamp(),
                    },
                    self,
                    handleResponse,
                );
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

    pub fn handleInput(self: *RawCli, key: Key) !void {
        return switch (self.state) {
            .userInput => try self.handleUserInput(key),
            .awaitingContinue => try self.handleAwaitingContinue(key),
            else => {},
        };
    }

    pub fn handleResponse(self: *RawCli, request: *const Request, response: *const Response) !void {
        self.has_more_results = switch (response.data) {
            .array => |arr| arr.items.len > 0,
            else => false,
        };
        if (request.kind != .continue_batch) {
            try self.writer.writeByte('\n');
        }
        try response.render(self.writer, self.has_more_results);

        try self.nextState();
        if (!self.has_more_results) {
            switch (response.data) {
                .array => try self.renderPrompt(),
                else => {},
            }
        }
    }

    fn handleUserInput(self: *RawCli, key: Key) !void {
        switch (key) {
            .arrow_up, .arrow_down => return,
            .char => |c| {
                if (c == Keys.ENTER) {
                    try self.nextState();
                } else if (c == Keys.BACKSPACE) {
                    if (self.input_buffer.items.len > 0) {
                        _ = self.input_buffer.pop();
                    }
                } else {
                    try self.input_buffer.append(self.allocator, c);
                }
            },
        }

        if (self.state != .awaitingContinue) {
            try self.renderPrompt();
        }
    }

    fn handleAwaitingContinue(self: *RawCli, key: Key) !void {
        switch (key) {
            .arrow_up, .arrow_down => {},
            .char => |c| {
                if (c == 'n' or c == 'N') {
                    try self.writer.writeAll("\r" ++ codes.ERASE_LINE);
                    try self.executor.sendRequest(
                        RawCli,
                        .{
                            .kind = .continue_batch,
                            .query = &[_]u8{},
                            .timestamp = std.time.microTimestamp(),
                        },
                        self,
                        handleResponse,
                    );
                } else {
                    self.has_more_results = false;
                    try self.nextState();
                    try self.renderPrompt();
                }
            },
        }
    }

    fn renderPrompt(self: *RawCli) !void {
        try self.writer.writeAll("\r" ++ codes.ERASE_LINE);
        try self.writer.writeAll(INPUT_PREFIX);
        try self.writer.writeAll(self.input_buffer.items);
    }
};
