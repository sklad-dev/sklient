const std = @import("std");
const posix = std.posix;

pub const Client = struct {
    allocator: std.mem.Allocator,
    host: [4]u8,
    port: u16,
    stream: ?std.net.Stream,
    read_buffer: []u8,

    const EMPTY_RESPONSE = [0]u8{};

    pub fn init(allocator: std.mem.Allocator, host: [4]u8, port: u16) !Client {
        return .{
            .allocator = allocator,
            .host = host,
            .port = port,
            .stream = null,
            .read_buffer = try allocator.alloc(u8, 4096),
        };
    }

    pub fn deinit(self: *Client) void {
        self.disconnect();
        self.allocator.free(self.read_buffer);
    }

    pub fn connect(self: *Client) !void {
        const address = std.net.Address.initIp4(self.host, self.port);
        self.stream = try std.net.tcpConnectToAddress(address);
    }

    pub fn disconnect(self: *Client) void {
        if (self.stream) |stream| {
            stream.close();
            self.stream = null;
        }
    }

    fn doSend(self: *Client, payload: []const u8) !void {
        var writer = self.stream.?.writer(&[0]u8{});
        try writer.interface.writeAll(payload);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }

    fn doReceive(self: *Client) ![]const u8 {
        @memset(self.read_buffer, 0);

        var reader = self.stream.?.reader(self.read_buffer);
        const r: *std.Io.Reader = reader.interface();

        while (try r.takeDelimiter('\n')) |response| {
            return response;
        }

        return &EMPTY_RESPONSE;
    }

    pub fn send(self: *Client, payload: []const u8) ![]const u8 {
        try self.doSend(payload);
        return try self.doReceive();
    }
};
