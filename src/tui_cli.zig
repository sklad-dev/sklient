const std = @import("std");
const codes = @import("codes.zig");
const query_builder = @import("query_builder.zig");

const Client = @import("client.zig").Client;
const Keys = @import("constants.zig").Keys;
const Response = @import("response.zig").Response;
const Request = @import("request.zig").Request;
const RequestKind = @import("request.zig").RequestKind;
const Layout = @import("layout.zig").Layout;
const History = @import("history.zig").History;
const ResultsRenderer = @import("results_renderer.zig").ResultsRenderer;

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
    layout: *Layout,
    history: *History,
    results_renderer: ResultsRenderer,
    has_more_results: bool = false,
    dropdown_visible: bool = false,

    const State = enum(u8) {
        empty,
        selectingQueryKind,
        providingParameters,
        executing,
        awaitingContinue,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        client: *Client,
        writer: *std.Io.Writer,
        layout: *Layout,
        history: *History,
    ) !TuiCli {
        return .{
            .allocator = allocator,
            .state = .empty,
            .query_builder = try query_builder.QueryBuilder.init(allocator),
            .request_buffer = try std.ArrayList(u8).initCapacity(allocator, 1024),
            .client = client,
            .writer = writer,
            .layout = layout,
            .history = history,
            .results_renderer = ResultsRenderer.init(allocator, layout),
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
                self.dropdown_visible = false;
                self.query_builder.setQuery() catch {
                    self.state = .selectingQueryKind;
                    return;
                };
                // Clear dropdown overlay from results area
                try self.results_renderer.clear();
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

        // Store command in history
        try self.history.addCommand(self.request_buffer.items);
        self.history.clearResults();

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

        // Check for errors
        if (response.value.errors) |err| {
            try self.results_renderer.renderError(err);
            self.has_more_results = false;
            try self.nextState();
            try self.renderPrompt();
            return;
        }

        // Render results based on type
        switch (response.value.data) {
            .null, .string, .integer, .float => {
                try self.results_renderer.renderScalar(response.value.data);
                self.has_more_results = false;
            },
            .array => |arr| {
                self.has_more_results = arr.items.len > 0;
                try self.results_renderer.renderKeyValuePairs(arr.items, self.has_more_results);
            },
            else => {
                self.has_more_results = false;
            },
        }

        if (self.has_more_results) {
            self.state = .awaitingContinue;
        } else {
            try self.nextState();
            try self.renderPrompt();
        }
    }

    fn executeContinueBatch(self: *TuiCli) !void {
        try self.sendRequest(.{
            .kind = .continue_batch,
            .query = &[_]u8{},
            .timestamp = std.time.microTimestamp(),
        });
    }

    fn handleEmpty(self: *TuiCli, key: u8) !void {
        if (key == ' ' or key == Keys.ENTER) {
            try self.nextState();
            try self.renderPrompt();
        }
    }

    fn handleSelectingQueryKind(self: *TuiCli, key: u8) !void {
        const dropdown = &self.query_builder.query_kind_dropdown.?;
        const options_num: u8 = @intCast(dropdown.options.len);

        switch (key) {
            Keys.ARROW_DOWN => {
                dropdown.selected_index = (dropdown.selected_index + 1) % options_num;
                self.dropdown_visible = true;
            },
            Keys.ARROW_UP => {
                dropdown.selected_index = if (dropdown.selected_index == 0) options_num - 1 else dropdown.selected_index - 1;
                self.dropdown_visible = true;
            },
            Keys.ENTER => {
                try self.nextState();
                try self.renderPrompt();
                return;
            },
            else => return,
        }

        try self.renderPrompt();
        if (self.dropdown_visible) {
            try self.renderDropdown();
        }
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
            try self.renderPrompt();
        }
    }

    fn handleAwaitingContinue(self: *TuiCli, key: u8) !void {
        if (key == 'n' or key == 'N') {
            try self.executeContinueBatch();
        } else {
            self.has_more_results = false;
            try self.nextState();
            try self.renderPrompt();
        }
    }

    fn renderPrompt(self: *TuiCli) !void {
        try self.layout.clearQueryLine();
        try self.writer.writeAll(INPUT_PREFIX);
        try self.query_builder.render(INPUT_PREFIX.len, self.writer);
    }

    fn renderDropdown(self: *TuiCli) !void {
        const dropdown = &self.query_builder.query_kind_dropdown.?;
        const offset_col: u16 = @intCast(INPUT_PREFIX.len + 3);
        try self.layout.drawDropdownOverlay(&dropdown.options, dropdown.selected_index, offset_col);
        try self.layout.positionCursorForInput();

        // Move cursor to end of input
        var buf: [32]u8 = undefined;
        const col: u16 = @intCast(INPUT_PREFIX.len + 12); // After query selector
        const move_cmd = codes.moveTo(&buf, 2, col);
        try self.writer.writeAll(move_cmd);
    }

    /// Render initial state when switching to this CLI mode
    pub fn renderInitial(self: *TuiCli) !void {
        try self.renderPrompt();
    }
};
