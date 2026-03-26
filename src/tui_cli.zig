const std = @import("std");
const codes = @import("codes.zig");
const query_builder = @import("query_builder.zig");

const Client = @import("client.zig").Client;
const Executor = @import("request.zig").Executor;
const Key = @import("constants.zig").Key;
const Keys = @import("constants.zig").Keys;
const Response = @import("response.zig").Response;
const Request = @import("request.zig").Request;
const RequestKind = @import("request.zig").RequestKind;
const QueryKind = @import("query.zig").QueryKind;

const INPUT_PREFIX = @import("constants.zig").INPUT_PREFIX;

pub const TuiCli = struct {
    allocator: std.mem.Allocator,
    state: State,
    query_builder: query_builder.QueryBuilder,
    executor: Executor,
    request_buffer: std.ArrayList(u8),
    writer: *std.Io.Writer,
    has_more_results: bool = false,

    const State = enum(u8) {
        empty,
        selectingQueryKind,
        providingParameters,
        executing,
        awaitingContinue,
    };

    pub fn init(allocator: std.mem.Allocator, client: *Client, writer: *std.Io.Writer) !TuiCli {
        return .{
            .allocator = allocator,
            .state = .empty,
            .query_builder = try query_builder.QueryBuilder.init(allocator),
            .executor = Executor.init(allocator, client),
            .request_buffer = try std.ArrayList(u8).initCapacity(allocator, 1024),
            .writer = writer,
        };
    }

    pub fn deinit(self: *TuiCli) void {
        self.request_buffer.deinit(self.allocator);
        self.query_builder.deinit();
    }

    pub fn nextState(self: *TuiCli) anyerror!void {
        switch (self.state) {
            .empty => self.state = .selectingQueryKind,
            .selectingQueryKind => {
                self.state = .providingParameters;
                self.query_builder.setQuery() catch {
                    self.state = .selectingQueryKind;
                    return;
                };
            },
            .providingParameters => {
                if (!(try self.query_builder.nextState())) {
                    self.state = .executing;
                    try self.executeQuery();
                }
            },
            .executing, .awaitingContinue => {
                if (!self.has_more_results) {
                    self.query_builder.deinit();
                    self.query_builder = try query_builder.QueryBuilder.init(self.allocator);
                    self.state = .empty;
                } else {
                    self.state = .awaitingContinue;
                }
            },
        }
    }

    pub fn handleInput(self: *TuiCli, key: Key) !void {
        return switch (self.state) {
            .empty => try self.handleEmpty(key),
            .selectingQueryKind => try self.handleSelectingQueryKind(key),
            .providingParameters => try self.handleProvidingParameters(key),
            .awaitingContinue => try self.handleAwaitingContinue(key),
            else => {},
        };
    }

    fn executeQuery(self: *TuiCli) !void {
        try self.query_builder.generateQueryString(
            self.allocator,
            &self.request_buffer,
        );
        defer self.request_buffer.clearRetainingCapacity();

        try self.renderPrompt(0);
        try self.executor.sendRequest(
            TuiCli,
            .{
                .kind = .query,
                .query = self.request_buffer.items,
                .timestamp = std.time.microTimestamp(),
            },
            self,
            handleResponse,
        );
    }

    pub fn handleResponse(self: *TuiCli, request: *const Request, response: *const Response) !void {
        self.has_more_results = switch (response.data) {
            .array => |arr| arr.items.len > 0,
            else => false,
        };
        if (request.kind != .continue_batch) {
            try self.writer.writeByte('\n');
        }
        try response.render(self.writer, self.has_more_results);

        if (self.has_more_results) {
            self.state = .awaitingContinue;
        } else {
            try self.nextState();
            switch (response.data) {
                .array => try self.renderPrompt(0),
                else => {},
            }
        }
    }

    fn handleEmpty(self: *TuiCli, key: Key) !void {
        if (key == .char and key.char == ' ') {
            try self.nextState();
            try self.renderPrompt(0);
        }
    }

    fn handleSelectingQueryKind(self: *TuiCli, key: Key) !void {
        const dropdown = &self.query_builder.query_kind_dropdown.?;
        const options_num: u8 = @intCast(dropdown.options.len);

        switch (key) {
            .arrow_down => dropdown.selected_index = (dropdown.selected_index + 1) % options_num,
            .arrow_up => dropdown.selected_index = if (dropdown.selected_index == 0) options_num - 1 else dropdown.selected_index - 1,
            .char => |c| {
                if (c == Keys.ENTER) {
                    try self.nextState();
                } else {
                    return;
                }
            },
        }

        try self.renderPrompt(options_num);
    }

    fn handleProvidingParameters(self: *TuiCli, key: Key) !void {
        switch (key) {
            .arrow_up, .arrow_down => return,
            .char => |c| {
                if (c == Keys.ENTER) {
                    try self.nextState();
                } else if (c == Keys.BACKSPACE) {
                    const buf = self.query_builder.activeBuffer().?;
                    if (buf.items.len > 0) _ = buf.pop();
                } else {
                    try self.query_builder.activeBuffer().?.append(self.allocator, c);
                }
            },
        }

        if (self.state != .awaitingContinue) {
            try self.renderPrompt(0);
        }
    }

    fn handleAwaitingContinue(self: *TuiCli, key: Key) !void {
        switch (key) {
            .arrow_up, .arrow_down => {},
            .char => |c| {
                if (c == 'n' or c == 'N') {
                    try self.clearLines(0);
                    try self.executor.sendRequest(
                        TuiCli,
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
                    try self.renderPrompt(0);
                }
            },
        }
    }

    fn renderPrompt(self: *TuiCli, lines_to_clean: u32) !void {
        try self.clearLines(lines_to_clean);
        try self.writer.writeAll(INPUT_PREFIX);
        try self.query_builder.render(INPUT_PREFIX.len, self.writer);
    }

    fn clearLines(self: *TuiCli, size: u32) !void {
        try self.writer.writeAll("\r" ++ codes.ERASE_LINE);
        for (0..size) |_| {
            try self.writer.writeAll(codes.MOVE_UP ++ "\r" ++ codes.ERASE_LINE);
        }
    }
};
