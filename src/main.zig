const std = @import("std");
const parser_mod = @import("parser.zig");
const execution_mod = @import("execution.zig");
const ArrayList = std.ArrayList;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const EnvMap = std.process.EnvMap;

const fork = std.posix.fork;
const pipe = std.posix.pipe;
const dup2 = std.posix.dup2;
const close = std.posix.close;
const execvp = std.posix.execvpeZ;
const execvpExpand = std.posix.execvpeZ_expandArg0;
const getEnvMap = std.process.getEnvMap;
const waitpid = std.posix.waitpid;

pub const fd_t = std.posix.fd_t;

const ChildProcess = std.process.Child;
pub fn main() !void {
    var gpa = GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();
    const stderr = std.io.getStdErr();

    const stdin_reader = stdin.reader();
    const stdout_writer = stdout.writer();
    const stderr_writer = stderr.writer();

    var to_parse = try ArrayList(u8).initCapacity(allocator, 256);
    defer to_parse.deinit();

    try stdout_writer.print("Welcome to the Zig Shell.\n", .{});

    const parser = parser_mod.Parser.init(allocator);
    const env_map = try getEnvMap(allocator);
    defer @constCast(&env_map).deinit();
    const null_t_env_map = try execution_mod.createNullDelimitedEnvMap(allocator, &env_map);
    defer execution_mod.freeEnvMap(allocator, null_t_env_map);

    while (true) {
        try stdout_writer.print("> ", .{});

        // here is when we block on reading from stdin until we got new commands
        stdin_reader.streamUntilDelimiter(to_parse.writer(), '\n', null) catch |err| {
            switch (err) {
                error.EndOfStream => {
                    break;
                },
                else => {},
            }
        };

        // parse the commands
        const commands = parser.parse(&to_parse, stdout_writer) catch |err| {
            if (err == error.ParseError) {
                try stderr_writer.print("Parse error\n", .{});
                continue;
            } else {
                std.debug.panic("{}", .{err});
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
                    try execution_mod.handle_first_child(null, argvc);
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

        // const last: *ChildProcess = @constCast(&childs.getLast());

        // const term = last.wait();

        // try stdout_writer.print("Term code: {any}\n", .{term});

        //try commands.print(stdout_writer);

        commands.destroy();
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
