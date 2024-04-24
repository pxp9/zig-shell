const std = @import("std");
pub const parser_mod = @import("parser.zig");
pub const Command = parser_mod.Command;
const Allocator = std.mem.Allocator;
const EnvMap = std.process.EnvMap;

pub const fd_t = std.posix.fd_t;
const dup2 = std.posix.dup2;
const close = std.posix.close;

fn redirection(descriptor_dup: i32, descriptor_close: i32) !void {
    try dup2(descriptor_close, descriptor_dup);
    close(descriptor_dup);
}

pub fn handle_first_child(
    pipe: ?[2]fd_t,
    argvc: u8,
) !void {
    // first command
    if (argvc > 1) {
        close(pipe.?[0]);
        try redirection(pipe.?[1], 1);
    }
}

pub fn createNullDelimitedEnvMap(arena: Allocator, env_map: *const EnvMap) ![:null]?[*:0]u8 {
    const envp_count = env_map.count();
    const envp_buf = try arena.allocSentinel(?[*:0]u8, envp_count, null);
    {
        var it = env_map.iterator();
        var i: usize = 0;
        while (it.next()) |pair| : (i += 1) {
            const env_buf = try arena.allocSentinel(u8, pair.key_ptr.len + pair.value_ptr.len + 1, 0);
            @memcpy(env_buf[0..pair.key_ptr.len], pair.key_ptr.*);
            env_buf[pair.key_ptr.len] = '=';
            @memcpy(env_buf[pair.key_ptr.len + 1 ..][0..pair.value_ptr.len], pair.value_ptr.*);
            envp_buf[i] = env_buf.ptr;
        }
    }
    return envp_buf;
}

pub fn freeArgv(alloc: Allocator, argv: [*:null]const ?[*:0]const u8) void {
    var i: u8 = 0;
    var val = argv[i];
    while (val) |arg| : ({
        i += 1;
        val = argv[i];
    }) {
        const len = std.mem.len(arg);
        const slice: []const u8 = arg[0 .. len + 1];
        alloc.free(slice);
    }
    const slice = std.mem.span(argv);
    alloc.free(slice);
}

pub fn freeEnvMap(alloc: Allocator, env_map: [*:null]?[*:0]u8) void {
    var i: u8 = 0;
    var val = env_map[i];
    while (val) |env| : ({
        i += 1;
        val = env_map[i];
    }) {
        const slice: []const u8 = env[0 .. std.mem.len(env) + 1];
        alloc.free(slice);
    }
    const slice = std.mem.span(env_map);
    alloc.free(slice);
}

// code to print null delimited strings

//    const v = argv[0].?;
//                 var i: u8 = 0;
//                 var l = v[i];
//                 while (l != 0) {
//                     try stdout_writer.print("{any},", .{l});
//                     i += 1;
//                     l = v[i];
//                 }
//                 try stdout_writer.print("{any}", .{l});
