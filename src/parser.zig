const std = @import("std");
const ArrayList = std.ArrayList;
const splitSequence = std.mem.splitSequence;
const trim = std.mem.trim;
const Allocator = std.mem.Allocator;
const copyForwards = std.mem.copyForwards;

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
    program: []const u8,
    args: Args,

    pub fn print(self: Command, stdout_writer: anytype) !void {
        try stdout_writer.print("Program: {s} ", .{self.program});
        try stdout_writer.print("Args: {s}\n", .{self.args.args.items});
    }

    pub fn destroy(self: Command) void {
        self.args.args.allocator.free(self.program);
        self.args.destroy();
    }
};

pub const Args = struct {
    args: ArrayList([]u8),
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
        var args = ArrayList([]u8).init(self.allocator);

        // Reserve space for the program name
        const program = try self.allocator.alloc(u8, val.?.len);
        copyForwards(u8, program, val.?);
        val = it.next();
        var argc: u8 = 0;
        while (val) |arg| : ({
            val = it.next();
            argc += 1;
        }) {

            // Reserve space for the argument
            const ptr = try self.allocator.alloc(u8, arg.len);
            copyForwards(u8, ptr, arg);

            try args.append(ptr);
        }
        return Command{ .program = program, .args = Args{ .args = args, .argc = argc } };
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
        while (val) |command| : ({
            val = it.next();
            argvc += 1;
        }) {
            if (command.len == 0) {
                destroy_commands(commands);
                return error.ParseError;
            }
            const command_trimmed = trim(u8, command, " \n\t");
            const cmd = self.parse_args(
                command_trimmed,
            ) catch |err| {
                if (err == error.ParseError) {
                    destroy_commands(commands);
                }
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
