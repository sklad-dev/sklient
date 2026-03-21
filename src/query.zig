const std = @import("std");
const InputField = @import("input_field.zig").InputField;

const delegate = @import("union_helpers.zig").delegate;
const delegateWithArg = @import("union_helpers.zig").delegateWithArg;
const delegateWithTwoArg = @import("union_helpers.zig").delegateWithTwoArg;

const DEFAULT_BUFFER_SIZE = 256;

pub const QueryKind = enum(u8) {
    set,
    get,
    getRange,
    delete,
};

const KEY_LABEL = "key";
const START_KEY_LABEL = "start key";
const END_KEY_LABEL = "end key";
const VALUE_LABEL = "value";
const TTL_LABEL = "expire";

pub const Query = union(QueryKind) {
    set: SetQuery,
    get: GetQuery,
    getRange: GetRangeQuery,
    delete: DeleteQuery,

    pub const activeBuffer = delegate(Query, "activeBuffer", anyerror!?*std.ArrayList(u8));
    pub const deinit = delegate(Query, "deinit", void);
    pub const nextState = delegate(Query, "nextState", anyerror!bool);
    pub const render = delegateWithArg(Query, "render", *std.Io.Writer, anyerror!void);
    pub const generateQueryString = delegateWithTwoArg(Query, "generateQueryString", std.mem.Allocator, *std.ArrayList(u8), anyerror!void);
};

pub const QueryField = struct {
    allocator: std.mem.Allocator,
    label: []const u8,
    buffer: std.ArrayList(u8),
    field: ?InputField,

    pub fn init(allocator: std.mem.Allocator, comptime label: []const u8) !QueryField {
        return .{
            .allocator = allocator,
            .label = label,
            .buffer = try std.ArrayList(u8).initCapacity(allocator, DEFAULT_BUFFER_SIZE),
            .field = null,
        };
    }

    pub inline fn deinit(self: *QueryField) void {
        self.buffer.deinit(self.allocator);
    }

    pub inline fn getField(self: *QueryField) *InputField {
        if (self.field == null) {
            self.field = InputField.init(self.label, &self.buffer);
        }
        return &self.field.?;
    }

    pub inline fn getBuffer(self: *QueryField) *std.ArrayList(u8) {
        return &self.buffer;
    }
};

pub fn MultiFieldQuery(comptime num_fields: u8, comptime labels: [num_fields][]const u8) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        fields: [num_fields]QueryField,
        current_field_index: u8,
        done: bool,

        pub fn init(allocator: std.mem.Allocator) !Self {
            var self = Self{
                .allocator = allocator,
                .fields = undefined,
                .current_field_index = 0,
                .done = false,
            };

            inline for (labels, 0..) |label, i| {
                self.fields[i] = try QueryField.init(allocator, label);
            }

            return self;
        }

        pub inline fn deinit(self: *Self) void {
            for (&self.fields) |*field| {
                field.deinit();
            }
        }

        pub inline fn activeBuffer(self: *Self) ?*std.ArrayList(u8) {
            if (self.done) return null;
            return &self.fields[self.current_field_index].buffer;
        }

        pub fn nextState(self: *Self) bool {
            if (self.done) return false;

            self.current_field_index += 1;
            if (self.current_field_index >= num_fields) {
                self.current_field_index = num_fields - 1;
                self.done = true;
                return false;
            }

            return true;
        }

        pub fn render(self: *Self, writer: *std.Io.Writer) !void {
            for (self.fields[0 .. self.current_field_index + 1], 0..) |*field, i| {
                if (i > 0) try writer.writeByte(' ');
                const is_active = !self.done and i == self.current_field_index;
                try (field.getField()).render(writer, is_active);
            }
        }

        pub fn generateQueryString(self: *Self, allocator: std.mem.Allocator, buffer: *std.ArrayList(u8)) !void {
            for (self.fields[0 .. self.current_field_index + 1]) |*field| {
                try buffer.append(allocator, ' ');
                try buffer.appendSlice(allocator, field.buffer.items);
            }
        }
    };
}

/// SetQuery with optional TTL support
/// Fields: key, value, expire (optional)
pub const SetQuery = struct {
    allocator: std.mem.Allocator,
    key_field: QueryField,
    value_field: QueryField,
    expire_field: QueryField,
    current_field_index: u8,
    done: bool,

    pub fn init(allocator: std.mem.Allocator) !SetQuery {
        return .{
            .allocator = allocator,
            .key_field = try QueryField.init(allocator, KEY_LABEL),
            .value_field = try QueryField.init(allocator, VALUE_LABEL),
            .expire_field = try QueryField.init(allocator, TTL_LABEL),
            .current_field_index = 0,
            .done = false,
        };
    }

    pub fn deinit(self: *SetQuery) void {
        self.key_field.deinit();
        self.value_field.deinit();
        self.expire_field.deinit();
    }

    pub fn activeBuffer(self: *SetQuery) ?*std.ArrayList(u8) {
        if (self.done) return null;
        return switch (self.current_field_index) {
            0 => &self.key_field.buffer,
            1 => &self.value_field.buffer,
            2 => &self.expire_field.buffer,
            else => null,
        };
    }

    pub fn nextState(self: *SetQuery) bool {
        if (self.done) return false;

        self.current_field_index += 1;
        // After value field, expire is optional
        // User can press enter with empty expire to skip it
        if (self.current_field_index >= 3) {
            self.current_field_index = 2;
            self.done = true;
            return false;
        }

        return true;
    }

    pub fn render(self: *SetQuery, writer: *std.Io.Writer) !void {
        const fields = [_]*QueryField{ &self.key_field, &self.value_field, &self.expire_field };

        for (fields[0 .. self.current_field_index + 1], 0..) |field, i| {
            if (i > 0) try writer.writeByte(' ');
            const is_active = !self.done and i == self.current_field_index;
            try (field.getField()).render(writer, is_active);
        }
    }

    pub fn generateQueryString(self: *SetQuery, allocator: std.mem.Allocator, buffer: *std.ArrayList(u8)) !void {
        // Format: set <key> <value> [expire '<duration>']
        try buffer.append(allocator, ' ');
        try buffer.appendSlice(allocator, self.key_field.buffer.items);
        try buffer.append(allocator, ' ');
        try buffer.appendSlice(allocator, self.value_field.buffer.items);

        // Add expire clause if specified
        if (self.expire_field.buffer.items.len > 0) {
            try buffer.appendSlice(allocator, " expire '");
            try buffer.appendSlice(allocator, self.expire_field.buffer.items);
            try buffer.append(allocator, '\'');
        }
    }
};

pub const GetQuery = MultiFieldQuery(1, [_][]const u8{KEY_LABEL});
pub const GetRangeQuery = MultiFieldQuery(2, [_][]const u8{ START_KEY_LABEL, END_KEY_LABEL });
pub const DeleteQuery = MultiFieldQuery(1, [_][]const u8{KEY_LABEL});
