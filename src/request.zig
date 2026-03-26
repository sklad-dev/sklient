const std = @import("std");

const Client = @import("client.zig").Client;
const Response = @import("response.zig").Response;

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

pub const Executor = struct {
    allocator: std.mem.Allocator,
    client: *Client,

    pub fn init(allocator: std.mem.Allocator, client: *Client) Executor {
        return .{
            .allocator = allocator,
            .client = client,
        };
    }

    pub fn sendRequest(
        self: *Executor,
        comptime ClientType: type,
        request: Request,
        handler: *ClientType,
        handle_response: fn (*ClientType, request: *const Request, response: *const Response) anyerror!void,
    ) !void {
        var json_writer = std.Io.Writer.Allocating.init(self.allocator);
        defer json_writer.deinit();
        try request.toString(&json_writer.writer);

        const request_bytes = try json_writer.toOwnedSlice();
        defer self.allocator.free(request_bytes);
        const response_bytes = try self.client.send(request_bytes);
        const response = try std.json.parseFromSlice(Response, self.allocator, response_bytes, .{});
        defer response.deinit();

        try handle_response(handler, &request, &response.value);
    }
};
