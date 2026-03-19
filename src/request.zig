const std = @import("std");

pub const RequestKind = enum(u8) {
    metric,
    query,
    continue_batch,
};

pub const Request = struct {
    kind: RequestKind,
    query: []const u8,
    timestamp: i64,

    pub inline fn toString(self: *const Request, writer: *std.Io.Writer) !void {
        try std.json.Stringify.value(self, .{ .whitespace = .minified }, writer);
    }
};
