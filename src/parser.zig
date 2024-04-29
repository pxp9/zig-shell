const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const copyForwards = std.mem.copyForwards;
const splitSequence = std.mem.splitSequence;
const trim = std.mem.trim;

pub const ShellError = error{
    ParseError,
};

pub const Commands = struct {
    commands: ArrayList(Command),
    argvc: u8,

    pub fn print(self: Commands, stdout_writer: anytype) !void {
        try stdout_writer.print("Number of Commands: {d} ", .{self.argvc});
        for (self.commands.items) |command| {
            try command.print(stdout_writer);
        }
    }

    pub fn destroy(self: Commands) void {
        for (self.commands.items) |command| {
            command.destroy();
        }
        self.commands.deinit();
    }
};

pub const Command = struct {
    args: Args,

    pub fn print(self: Command, stdout_writer: anytype) !void {
        try stdout_writer.print("Program: {s} ", .{self.args.args.items[0]});
        try stdout_writer.print("Args: {s}\n", .{self.args.args.items[1 .. self.args.argc - 1]});
    }

    pub fn destroy(self: Command) void {
        self.args.destroy();
    }

    // wtf is this ?
    // the main reason of this is C
    // C needs null terminated array of strings
    // and each string is a null terminated array of chars

    pub fn toArgv(self: Command, alloc: Allocator) ![*:null]const ?[*:0]const u8 {
        const argv: [:null]?[*:0]u8 = try alloc.allocSentinel(?[*:0]u8, self.args.argc, null);
        for (self.args.args.items, 0..) |arg, i| {
            const len = self.args.args.items[i].len;
            const n_arg = try alloc.allocSentinel(u8, len, 0);
            @memcpy(n_arg[0..arg.len], arg);
            argv[i] = n_arg;
        }
        return argv;
    }
};

pub const Args = struct {
    args: ArrayList([]const u8),
    argc: u8,

    pub fn destroy(self: Args) void {
        for (self.args.items) |arg| {
            self.args.allocator.free(arg);
        }
        self.args.deinit();
    }
};

pub const Parser = struct {
    allocator: Allocator,
    const Self = @This();

    pub fn init(alloc: Allocator) Self {
        return Parser{ .allocator = alloc };
    }

    pub fn parse_args(self: Self, command_trimmed: []const u8) !Command {
        var it = splitSequence(u8, command_trimmed, " ");
        var val = it.next();
        if (val == null) {
            return error.ParseError;
        }
        var args = ArrayList([]const u8).init(self.allocator);
        var argc: u8 = 0;
        while (val) |arg| : ({
            val = it.next();
            argc += 1;
        }) {

            // Reserve space for the argument
            const ptr: []const u8 = try self.allocator.alloc(u8, arg.len);
            copyForwards(u8, @constCast(ptr), arg);

            try args.append(ptr);
        }
        return Command{ .args = Args{ .args = args, .argc = argc } };
    }

    fn destroy_commands(commands: ArrayList(Command)) void {
        for (commands.items) |command| {
            command.destroy();
        }
        commands.deinit();
    }

    pub fn parse_pipes(self: Self, text: *ArrayList(u8), stdout_writer: anytype) !Commands {
        _ = stdout_writer;

        var it = splitSequence(u8, text.items, "|");
        var val = it.next();
        var argvc: u8 = 0;
        var commands = ArrayList(Command).init(self.allocator);
        errdefer destroy_commands(commands);
        while (val) |command| : ({
            val = it.next();
            argvc += 1;
        }) {
            if (command.len == 0) {
                return error.ParseError;
            }
            const command_trimmed = trim(u8, command, " \n\t");
            const cmd = self.parse_args(
                command_trimmed,
            ) catch |err| {
                return err;
            };

            // try cmd.print(stdout_writer);

            try commands.append(cmd);
        }

        return Commands{ .commands = commands, .argvc = argvc };
    }

    pub fn parse(self: Self, text: *ArrayList(u8), stdout_writer: anytype) !Commands {
        const commands = self.parse_pipes(text, stdout_writer) catch |err| {
            if (err == error.ParseError) {
                text.clearRetainingCapacity();
            }
            return err;
        };

        text.clearRetainingCapacity();

        return commands;
    }
};

pub fn getLineAndParse(
    stdin_reader: anytype,
    stdout_writer: anytype,
    to_parse: *ArrayList(u8),
    parser: Parser,
) !Commands {

    // here is when we block on reading from stdin until we got new commands
    try stdin_reader.streamUntilDelimiter(to_parse.writer(), '\n', null);

    // parse the commands
    const commands = try parser.parse(to_parse, stdout_writer);

    return commands;
}
