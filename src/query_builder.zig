const std = @import("std");
const Dropdown = @import("dropdown.zig").Dropdown;
const InputField = @import("input_field.zig").InputField;
const Query = @import("query.zig").Query;
const DeleteQuery = @import("query.zig").DeleteQuery;
const GetQuery = @import("query.zig").GetQuery;
const GetRangeQuery = @import("query.zig").GetRangeQuery;
const SetQuery = @import("query.zig").SetQuery;
const QueryKind = @import("query.zig").QueryKind;

pub const QueryBuilder = struct {
    allocator: std.mem.Allocator,
    query: ?Query,
    query_kind_dropdown: ?QueryKindDropdown,
    input_field: ?InputField,

    const QueryKindDropdown = Dropdown(
        4,
        "query",
        [_][]const u8{
            "set",
            "get",
            "get range",
            "delete",
        },
    );

    pub fn init(allocator: std.mem.Allocator) !QueryBuilder {
        return QueryBuilder{
            .allocator = allocator,
            .query = null,
            .query_kind_dropdown = null,
            .input_field = null,
        };
    }

    pub fn deinit(self: *QueryBuilder) void {
        if (self.query) |*q| q.deinit();
    }

    pub fn activeBuffer(self: *QueryBuilder) !?*std.ArrayList(u8) {
        if (self.query) |*q| return q.activeBuffer();

        return null;
    }

    pub fn setQuery(self: *QueryBuilder) !void {
        const kind: QueryKind = @enumFromInt(self.query_kind_dropdown.?.selected_index);
        switch (kind) {
            .set => self.query = Query{ .set = try SetQuery.init(self.allocator) },
            .get => self.query = Query{ .get = try GetQuery.init(self.allocator) },
            .delete => self.query = Query{ .delete = try DeleteQuery.init(self.allocator) },
            .getRange => self.query = Query{ .getRange = try GetRangeQuery.init(self.allocator) },
        }
    }

    pub fn render(self: *QueryBuilder, comptime dropdown_offset: u32, writer: *std.Io.Writer) !void {
        if (self.query) |*q| {
            try self.query_kind_dropdown.?.renderSelectedOption(writer);
            try q.render(writer);
        } else {
            if (self.query_kind_dropdown == null) {
                self.query_kind_dropdown = QueryKindDropdown{};
                try self.query_kind_dropdown.?.renderQueryKindSelector(writer);
            } else {
                try self.query_kind_dropdown.?.render(dropdown_offset, writer);
            }
        }
    }

    pub fn generateQueryString(self: *QueryBuilder, allocator: std.mem.Allocator, buffer: *std.ArrayList(u8)) !void {
        try buffer.appendSlice(allocator, self.query_kind_dropdown.?.selected());
        try self.query.?.generateQueryString(allocator, buffer);
    }

    pub fn nextState(self: *QueryBuilder) !bool {
        if (self.query) |*q| return try q.nextState();

        return false;
    }
};
