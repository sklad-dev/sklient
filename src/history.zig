const std = @import("std");

/// History manager using arena allocator for storing commands and results.
/// Results from the last query are kept while on screen, then cleared for new queries.
pub const History = struct {
    /// Arena allocator for history storage
    arena: std.heap.ArenaAllocator,
    /// Backing allocator
    backing_allocator: std.mem.Allocator,
    /// Command history (persisted across queries)
    commands: std.ArrayList([]const u8),
    /// Current result lines (cleared on new query)
    result_lines: std.ArrayList([]const u8),
    /// Current command index for navigation
    current_index: usize,
    /// Maximum number of commands to keep
    max_commands: usize,

    const DEFAULT_MAX_COMMANDS = 100;

    pub fn init(backing_allocator: std.mem.Allocator) History {
        const arena = std.heap.ArenaAllocator.init(backing_allocator);

        return .{
            .arena = arena,
            .backing_allocator = backing_allocator,
            .commands = .{},
            .result_lines = .{},
            .current_index = 0,
            .max_commands = DEFAULT_MAX_COMMANDS,
        };
    }

    pub fn deinit(self: *History) void {
        // ArrayList items are allocated in arena, no need to free individually
        self.arena.deinit();
    }

    /// Add a command to history
    pub fn addCommand(self: *History, command: []const u8) !void {
        if (command.len == 0) return;

        const allocator = self.arena.allocator();

        // Don't add duplicates of the last command
        if (self.commands.items.len > 0) {
            const last = self.commands.items[self.commands.items.len - 1];
            if (std.mem.eql(u8, last, command)) {
                self.current_index = self.commands.items.len;
                return;
            }
        }

        // If at max capacity, we need to remove oldest
        if (self.commands.items.len >= self.max_commands) {
            // Reset arena and rebuild history (excluding oldest entry)
            try self.compactCommands();
        }

        // Copy command string into arena
        const owned_command = try allocator.dupe(u8, command);
        try self.commands.append(allocator, owned_command);
        self.current_index = self.commands.items.len;
    }

    /// Navigate to previous command in history
    pub fn previousCommand(self: *History) ?[]const u8 {
        if (self.commands.items.len == 0) return null;
        if (self.current_index > 0) {
            self.current_index -= 1;
        }
        return self.commands.items[self.current_index];
    }

    /// Navigate to next command in history
    pub fn nextCommand(self: *History) ?[]const u8 {
        if (self.commands.items.len == 0) return null;
        if (self.current_index < self.commands.items.len - 1) {
            self.current_index += 1;
            return self.commands.items[self.current_index];
        }
        // At end of history, return empty to allow new input
        self.current_index = self.commands.items.len;
        return null;
    }

    /// Get current command (if navigating history)
    pub fn currentCommand(self: *History) ?[]const u8 {
        if (self.current_index < self.commands.items.len) {
            return self.commands.items[self.current_index];
        }
        return null;
    }

    /// Clear current results and prepare for new query results
    pub fn clearResults(self: *History) void {
        self.result_lines.clearRetainingCapacity();
    }

    /// Add a result line to current results
    pub fn addResultLine(self: *History, line: []const u8) !void {
        const allocator = self.arena.allocator();
        const owned_line = try allocator.dupe(u8, line);
        try self.result_lines.append(allocator, owned_line);
    }

    /// Get all current result lines
    pub fn getResultLines(self: *History) []const []const u8 {
        return self.result_lines.items;
    }

    /// Get number of stored commands
    pub fn commandCount(self: *History) usize {
        return self.commands.items.len;
    }

    /// Reset navigation index to end of history
    pub fn resetNavigation(self: *History) void {
        self.current_index = self.commands.items.len;
    }

    fn compactCommands(self: *History) !void {
        // Save commands we want to keep (drop the oldest one)
        var temp: std.ArrayList([]const u8) = .{};
        defer temp.deinit(self.backing_allocator);

        const start_idx: usize = 1; // Skip oldest
        for (self.commands.items[start_idx..]) |cmd| {
            const duped = try self.backing_allocator.dupe(u8, cmd);
            try temp.append(self.backing_allocator, duped);
        }

        // Reset arena
        _ = self.arena.reset(.free_all);
        const allocator = self.arena.allocator();

        // Rebuild commands list
        self.commands = .{};
        self.result_lines = .{};

        for (temp.items) |cmd| {
            const owned = try allocator.dupe(u8, cmd);
            try self.commands.append(allocator, owned);
            self.backing_allocator.free(cmd);
        }
    }
};

test "history basic operations" {
    var history = History.init(std.testing.allocator);
    defer history.deinit();

    try history.addCommand("set foo 'bar'");
    try history.addCommand("get foo");

    try std.testing.expectEqual(@as(usize, 2), history.commandCount());

    const prev = history.previousCommand();
    try std.testing.expect(prev != null);
    try std.testing.expectEqualStrings("get foo", prev.?);

    const prev2 = history.previousCommand();
    try std.testing.expectEqualStrings("set foo 'bar'", prev2.?);
}
