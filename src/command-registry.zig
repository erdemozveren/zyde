const std = @import("std");

const serde = @import("serde");
const Window = @import("root.zig").Window;

pub const Context = struct {
    allocator: std.mem.Allocator,
    window: *Window,
};

pub const Response = union(enum) {
    void,
    json: [:0]u8,

    pub fn deinit(
        self: Response,
        allocator: std.mem.Allocator,
    ) void {
        switch (self) {
            .void => {},
            .json => |bytes| allocator.free(bytes),
        }
    }
};

const Handler = *const fn (
    *Context,
    []const u8,
) anyerror!Response;

const CommandMap = std.StaticStringMap(Handler);

pub fn Registry(comptime Commands: anytype) type {
    const commands = buildCommands(Commands);

    return struct {
        pub fn call(
            context: *Context,
            name: []const u8,
            args_json: []const u8,
        ) !Response {
            const handler = commands.get(name) orelse
                return error.UnknownCommand;

            return handler(context, args_json);
        }
    };
}

fn buildCommands(
    comptime Commands: anytype,
) CommandMap {
    const info = @typeInfo(@TypeOf(Commands)).@"struct";

    const groups = if (info.is_tuple)
        Commands
    else
        .{Commands};

    var count: usize = 0;

    inline for (groups) |group| {
        count += @typeInfo(@TypeOf(group)).@"struct".fields.len;
    }

    var entries: [count]struct {
        []const u8,
        Handler,
    } = undefined;

    var index: usize = 0;

    inline for (groups) |group| {
        const fields =
            @typeInfo(@TypeOf(group)).@"struct".fields;

        inline for (fields) |field| {
            entries[index] = .{
                field.name,
                makeHandler(@field(group, field.name)),
            };

            index += 1;
        }
    }

    return CommandMap.initComptime(entries);
}

fn validateCommand(
    comptime name: []const u8,
    comptime info: std.builtin.Type.Fn,
) void {
    if (info.is_generic)
        @compileError(
            "Command '" ++ name ++ "' cannot be generic",
        );

    if (info.is_var_args)
        @compileError(
            "Command '" ++ name ++ "' cannot be variadic",
        );

    inline for (info.params) |param| {
        if (param.type == null)
            @compileError(
                "Command '" ++ name ++
                    "' has an invalid parameter",
            );
    }

    if (info.return_type == null)
        @compileError(
            "Command '" ++ name ++
                "' must have a return type",
        );
}

fn makeHandler(
    comptime command: anytype,
) Handler {
    return struct {
        fn handler(
            context: *Context,
            args_json: []const u8,
        ) !Response {
            return invokeCommand(
                context,
                command,
                args_json,
            );
        }
    }.handler;
}

fn invokeCommand(
    context: *Context,
    comptime command: anytype,
    args_json: []const u8,
) !Response {
    const info = @typeInfo(@TypeOf(command)).@"fn";
    const ReturnType = info.return_type.?;

    const has_context = comptime blk: {
        if (info.params.len == 0)
            break :blk false;

        break :blk info.params[0].type.? == *Context;
    };

    const start = if (has_context) 1 else 0;
    const arg_count = info.params.len - start;

    if (comptime arg_count == 0) {
        if (comptime has_context) {
            return makeResponse(
                context.allocator,
                ReturnType,
                try command(context),
            );
        }

        return makeResponse(
            context.allocator,
            ReturnType,
            try command(),
        );
    }

    const Args = std.meta.Tuple(
        comptime blk: {
            var types: [arg_count]type = undefined;

            for (info.params[start..], 0..) |param, i| {
                types[i] = param.type.?;
            }

            break :blk &types;
        },
    );

    const args = try serde.json.fromSlice(
        Args,
        context.allocator,
        args_json,
    );

    if (comptime has_context) {
        var all_args: std.meta.ArgsTuple(@TypeOf(command)) = undefined;

        all_args[0] = context;

        inline for (1..info.params.len) |i| {
            all_args[i] = args[i - 1];
        }

        if (comptime @typeInfo(ReturnType) == .error_union) {
            return makeResponse(
                context.allocator,
                ReturnType,
                try @call(.auto, command, all_args),
            );
        }

        return makeResponse(
            context.allocator,
            ReturnType,
            @call(.auto, command, all_args),
        );
    }

    if (comptime @typeInfo(ReturnType) == .error_union) {
        return makeResponse(
            context.allocator,
            ReturnType,
            try @call(.auto, command, args),
        );
    }

    return makeResponse(
        context.allocator,
        ReturnType,
        @call(.auto, command, args),
    );
}

fn makeResponse(
    allocator: std.mem.Allocator,
    comptime ReturnType: type,
    result: anytype,
) !Response {
    const ResultType = switch (@typeInfo(ReturnType)) {
        .error_union => |info| info.payload,
        else => ReturnType,
    };

    if (ResultType == void)
        return .void;

    const json = try serde.json.toSliceAlloc(
        allocator,
        result,
    );

    return .{
        .json = json,
    };
}
