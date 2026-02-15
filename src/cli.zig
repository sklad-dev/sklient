const std = @import("std");

const QueryKind = enum(u8) {
    set,
    get,
    getRange,
    delete,
};

pub const INPUT_PREFIX = "sklient % ";

pub const Cli = struct {
    allocator: std.mem.Allocator,
    state: State,
    request_buffer: []u8,
    response_buffer: []u8,

    const State = enum(u8) {
        empty,
        selectingQueryKind,
        providingParameters,
        executing,
        awaitingContinue,
    };

    pub fn init(allocator: std.mem.Allocator) !Cli {
        const request_buffer = try allocator.alloc(u8, 4096);
        const response_buffer = try allocator.alloc(u8, 4096);

        return Cli{
            .allocator = allocator,
            .state = .empty,
            .request_buffer = request_buffer,
            .response_buffer = response_buffer,
        };
    }

    pub fn deinit(self: *Cli) void {
        self.allocator.free(self.request_buffer);
        self.allocator.free(self.response_buffer);
    }

    pub fn nextState(self: *Cli) void {
        switch (self.state) {
            .empty => self.state = .selectingQueryKind,
            .selectingQueryKind => self.state = .providingParameters,
            .providingParameters => self.state = .executing,
            .executing => self.state = .empty,
            .awaitingContinue => self.state = .empty,
        }
    }
};
