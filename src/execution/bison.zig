const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const execution_mod = @import("../execution.zig");

const fork = std.posix.fork;
const execvpExpand = std.posix.execvpeZ_expandArg0;
pub const fd_t = std.posix.fd_t;
const pipe = std.posix.pipe;
const waitpid = std.posix.waitpid;
const close = std.posix.close;
const getpid = std.os.linux.getpid;

extern fn obtain_order(arg_argvvp: [*c][*c][*c][*c]u8, arg_filep: [*c][3]u8, arg_bgp: [*c]c_int) c_int;

pub fn mainBisonParser(stdout_writer: anytype, stdin_reader: anytype, stderr_writer: anytype, allocator: Allocator, null_t_env_map: [*:null]const ?[*:0]const u8) !void {
    _ = stdin_reader;
    _ = stderr_writer;

    var filev: [3]?[*:0]u8 = .{ null, null, null };

    var argvv: [*c][*c][*c]u8 = null;
    var bg: c_int = 0;

    while (true) {
        try stdout_writer.print("{d}> ", .{getpid()});

        const ret: i32 = obtain_order(@ptrCast(&argvv), @ptrCast(&filev), @ptrCast(&bg));

        if (ret == 0) {
            try stdout_writer.print("\nGoodbye!\n", .{});
            break;
        }

        if (ret == -1) continue;

        const argvc: usize = @intCast(ret - 1);

        if (argvc == 0) continue;

        try stdout_writer.print("Argvc: {}\n", .{argvc});
        try stdout_writer.print("{s}\n", .{argvv[0][0]});
        try printCString("filev[0] = ", filev[0], stdout_writer);

        var child_pids: ArrayList(i32) = ArrayList(i32).init(allocator);
        defer child_pids.deinit();
        var pipes = try ArrayList([2]fd_t).initCapacity(allocator, argvc - 1);
        defer pipes.deinit();

        if (argvc >= 2)
            try pipes.append(try pipe());

        for (0..argvc) |i| {
            const pid = try fork();

            if (pid == 0) {
                // child
                if (i == 0) {
                    try execution_mod.handle_first_child(pipes, @intCast(argvc));
                } else if (i < argvc - 1) {} else {
                    try execution_mod.handle_last_child(pipes.items[i - 1]);
                }
                const err = execvpExpand(.no_expand, argvv[i][0], argvv[i], null_t_env_map);
                try std.debug.panic("{}", .{err});
            } else {
                try child_pids.append(pid);
                // parent
                if (i == 0) {
                    // first command
                    if (i + 1 < argvc - 1) {
                        try stdout_writer.print("First command with pipe\n", .{});
                        try pipes.append(try pipe());
                    }

                    if (argvc > 1) {
                        // close the write end of the pipe
                        close(pipes.items[i][1]);
                    } else {
                        const last_pid: i32 = child_pids.getLast();

                        const status = waitpid(last_pid, 0);

                        _ = status;
                    }
                } else if (i < argvc - 1) {
                    // middle command
                    try stdout_writer.print("Middle command with pipe\n", .{});
                } else {
                    const last_pid: i32 = child_pids.getLast();

                    const status = waitpid(last_pid, 0);

                    _ = status;
                    // close the read end of the previous pipe
                    if (argvc > 1)
                        close(pipes.items[i - 1][0]);
                }
            }
        }
    }
}

// to use this function, you must ensure that the cstr is null-terminated
fn printCString(fmt: []const u8, cstr: ?[*:0]u8, stdout_writer: anytype) !void {
    if (cstr == null) {
        return;
    }

    try stdout_writer.print("{s}", .{fmt});

    const str = cstr.?;

    var i: usize = 0;
    while (str[i] != 0) {
        try stdout_writer.print("{c}", .{str[i]});
        i += 1;
    }
    try stdout_writer.print("\n", .{});
}
