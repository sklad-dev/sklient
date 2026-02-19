const std = @import("std");
const codes = @import("codes.zig");
const query_builder = @import("query_builder.zig");

const Client = @import("client.zig").Client;
const Keys = @import("constants.zig").Keys;
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
            .executing => {
                self.query_builder.deinit();
                self.query_builder = try query_builder.QueryBuilder.init(self.allocator);
                self.state = .empty;
            },
            .awaitingContinue => self.state = .empty,
        }
    }

    pub fn handleInput(self: *TuiCli, key: u8) !void {
        return switch (self.state) {
            .empty => try self.handleEmpty(key),
            .selectingQueryKind => try self.handleSelectingQueryKind(key),
            .providingParameters => try self.handleProvidingParameters(key),
            else => {},
        };
    }

    pub fn executeQuery(self: *TuiCli) !void {
        try self.query_builder.generateQueryString(
            self.allocator,
            &self.request_buffer,
        );
        defer self.request_buffer.clearRetainingCapacity();

        const req = Request{
            .kind = .query,
            .query = self.request_buffer.items,
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
        } else {
            try (try self.query_builder.activeBuffer()).?.append(self.allocator, key);
        }
        try self.renderPrompt(0);
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
