const std = @import("std");
const query_builder = @import("query_builder.zig");

const QueryKind = enum(u8) {
    set,
    get,
    getRange,
    delete,
};

pub const INPUT_PREFIX = "sklient> ";

pub const Cli = struct {
    allocator: std.mem.Allocator,
    state: State,
    query_builder: query_builder.QueryBuilder,
    request_buffer: std.ArrayList(u8),

    const State = enum(u8) {
        empty,
        selectingQueryKind,
        providingParameters,
        executing,
        awaitingContinue,
    };

    pub fn init(allocator: std.mem.Allocator) !Cli {
        return Cli{
            .allocator = allocator,
            .state = .empty,
            .query_builder = try query_builder.QueryBuilder.init(allocator),
            .request_buffer = try std.ArrayList(u8).initCapacity(allocator, 1024),
        };
    }

    pub fn deinit(self: *Cli) void {
        self.request_buffer.deinit(self.allocator);
        self.query_builder.deinit();
    }

    pub fn nextState(self: *Cli) !void {
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
                }
            },
            .executing => self.state = .empty,
            .awaitingContinue => self.state = .empty,
        }
    }
};
