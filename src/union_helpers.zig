pub fn delegate(
    comptime Self: type,
    comptime method_name: []const u8,
    comptime ReturnType: type,
) fn (*Self) ReturnType {
    return struct {
        fn func(self: *Self) ReturnType {
            return switch (self.*) {
                inline else => |*variant| @call(.auto, @field(@TypeOf(variant.*), method_name), .{variant}),
            };
        }
    }.func;
}

pub fn delegateWithArg(
    comptime Self: type,
    comptime method_name: []const u8,
    comptime ArgType: type,
    comptime ReturnType: type,
) fn (*Self, ArgType) ReturnType {
    return struct {
        fn func(self: *Self, arg: ArgType) ReturnType {
            return switch (self.*) {
                inline else => |*variant| @call(.auto, @field(@TypeOf(variant.*), method_name), .{ variant, arg }),
            };
        }
    }.func;
}

pub fn delegateWithTwoArg(
    comptime Self: type,
    comptime method_name: []const u8,
    comptime FirstArgType: type,
    comptime SecondArgType: type,
    comptime ReturnType: type,
) fn (*Self, FirstArgType, SecondArgType) ReturnType {
    return struct {
        fn func(self: *Self, arg1: FirstArgType, arg2: SecondArgType) ReturnType {
            return switch (self.*) {
                inline else => |*variant| @call(.auto, @field(@TypeOf(variant.*), method_name), .{ variant, arg1, arg2 }),
            };
        }
    }.func;
}
