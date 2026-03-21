const std = @import("std");
const codes = @import("codes.zig");
const query_builder = @import("query_builder.zig");

const Client = @import("client.zig").Client;
const Keys = @import("constants.zig").Keys;
const Response = @import("response.zig").Response;
const Request = @import("request.zig").Request;
const RequestKind = @import("request.zig").RequestKind;

const INPUT_PREFIX = @import("constants.zig").INPUT_PREFIX;

const QueryKind = enum(u8) {
    set,
    get,
    getRange,
    delete,
};

pub const TuiCli = struct {
    allocator: std.mem.Allocator,
    state: State,
    query_builder: query_builder.QueryBuilder,
    request_buffer: std.ArrayList(u8),
    client: *Client,
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
            .request_buffer = try std.ArrayList(u8).initCapacity(allocator, 1024),
            .client = client,
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

    pub fn handleInput(self: *TuiCli, key: u8) !void {
        return switch (self.state) {
            .empty => try self.handleEmpty(key),
            .selectingQueryKind => try self.handleSelectingQueryKind(key),
            .providingParameters => try self.handleProvidingParameters(key),
            .awaitingContinue => try self.handleAwaitingContinue(key),
            else => {},
        };
    }

    pub fn executeQuery(self: *TuiCli) !void {
        try self.query_builder.generateQueryString(
            self.allocator,
            &self.request_buffer,
        );
        defer self.request_buffer.clearRetainingCapacity();

        try self.renderPrompt(0);
        try self.sendRequest(.{
            .kind = .query,
            .query = self.request_buffer.items,
            .timestamp = std.time.microTimestamp(),
        });
    }

    fn sendRequest(self: *TuiCli, req: Request) !void {
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

        if (self.has_more_results) {
            self.state = .awaitingContinue;
        } else {
            try self.nextState();
            switch (response.value.data) {
                .array => try self.renderPrompt(0),
                else => {},
            }
        }
    }

    fn executeContinueBatch(self: *TuiCli) !void {
        try self.clearLines(0);
        try self.sendRequest(.{
            .kind = .continue_batch,
            .query = &[_]u8{},
            .timestamp = std.time.microTimestamp(),
        });
    }

    fn handleEmpty(self: *TuiCli, key: u8) !void {
        if (key == ' ') {
            try self.nextState();
            try self.renderPrompt(0);
        }
    }

    fn handleSelectingQueryKind(self: *TuiCli, key: u8) !void {
        const dropdown = &self.query_builder.query_kind_dropdown.?;
        const options_num: u8 = @intCast(dropdown.options.len);

        switch (key) {
            Keys.ARROW_DOWN => dropdown.selected_index = (dropdown.selected_index + 1) % options_num,
            Keys.ARROW_UP => dropdown.selected_index = if (dropdown.selected_index == 0) options_num - 1 else dropdown.selected_index - 1,
            Keys.ENTER => try self.nextState(),
            else => return,
        }

        try self.renderPrompt(options_num);
    }

    fn handleProvidingParameters(self: *TuiCli, key: u8) !void {
        if (key == Keys.ENTER) {
            try self.nextState();
        } else if (key == Keys.BACKSPACE) {
            _ = (try self.query_builder.activeBuffer()).?.pop();
        } else if (key == Keys.ARROW_UP or key == Keys.ARROW_DOWN) {
            return;
        } else {
            try (try self.query_builder.activeBuffer()).?.append(self.allocator, key);
        }

        if (self.state != .awaitingContinue) {
            try self.renderPrompt(0);
        }
    }

    fn handleAwaitingContinue(self: *TuiCli, key: u8) !void {
        if (key == 'n' or key == 'N') {
            try self.executeContinueBatch();
        } else {
            self.has_more_results = false;
            try self.nextState();
            try self.renderPrompt(0);
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
