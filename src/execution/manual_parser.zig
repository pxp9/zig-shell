const std = @import("std");
const manual_parser = @import("../parser.zig");
const execution_mod = @import("../execution.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const fork = std.posix.fork;
const execvpExpand = std.posix.execvpeZ_expandArg0;
pub const fd_t = std.posix.fd_t;
const pipe = std.posix.pipe;
const waitpid = std.posix.waitpid;
const close = std.posix.close;

pub fn mainManualParser(stdout_writer: anytype, stdin_reader: anytype, stderr_writer: anytype, allocator: Allocator, null_t_env_map: [*:null]?[*:0]u8) !void {
    var to_parse = try ArrayList(u8).initCapacity(allocator, 256);
    defer to_parse.deinit();

    const parser = manual_parser.Parser.init(allocator);

    while (true) {
        try stdout_writer.print("> ", .{});

        var commands = manual_parser.getLineAndParse(stdin_reader, stdout_writer, &to_parse, parser) catch |err| {
            switch (err) {
                error.ParseError => {
                    try stderr_writer.print("Parse error\n", .{});
                    continue;
                },
                error.EndOfStream => {
                    try stdout_writer.print("\nGoodbye!\n", .{});
                    break;
                },
                else => {
                    std.debug.panic("{}", .{err});
                },
            }
        };

        var child_pids: ArrayList(i32) = ArrayList(i32).init(allocator);
        defer child_pids.deinit();
        var pipes = try ArrayList([2]fd_t).initCapacity(allocator, commands.argvc - 1);
        defer pipes.deinit();

        if (commands.argvc > 1) {
            try pipes.insert(0, try pipe());
        }

        var n: u8 = 0;
        const argvc = commands.argvc;
        // execute the commands
        for (commands.commands.items) |command| {
            const argv = try command.toArgv(allocator);
            defer execution_mod.freeArgv(allocator, argv);

            const pid = try fork();

            if (pid == 0) {
                // child
                if (n == 0) {
                    try execution_mod.handle_first_child(pipes, argvc);
                }
                const err = execvpExpand(.no_expand, argv[0].?, argv, null_t_env_map);
                try std.debug.panic("{}", .{err});
            } else {
                // parent
                if (n == 0) {
                    // first command
                    if (n + 1 < argvc - 1) {
                        //pipe(fd[i + 1]);
                    }

                    if (argvc > 1) {
                        // close the write end of the pipe
                        close(pipes.items[n][1]);
                    }
                }
                try child_pids.append(pid);
            }

            n += 1;
        }

        const last_pid: i32 = child_pids.getLast();

        const status = waitpid(last_pid, 0);

        _ = status;

        commands.destroy();
    }
}
