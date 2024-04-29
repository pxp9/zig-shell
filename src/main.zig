const std = @import("std");
const parser_mod = @import("execution/manual_parser.zig");
const execution_mod = @import("execution.zig");
const bison_mod = @import("execution/bison.zig");
const ArrayList = std.ArrayList;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const EnvMap = std.process.EnvMap;
const Commands = parser_mod.Commands;

const mainManualParser = parser_mod.mainManualParser;
const mainBisonParser = bison_mod.mainBisonParser;

const eql = std.mem.eql;
const argsWithAllocator = std.process.argsWithAllocator;
const pipe = std.posix.pipe;
const dup2 = std.posix.dup2;
const getEnvMap = std.process.getEnvMap;
pub const fd_t = std.posix.fd_t;

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

    try stdout_writer.print("\nWelcome to the Zig Shell.\n", .{});
    const env_map = try getEnvMap(allocator);
    defer @constCast(&env_map).deinit();
    const null_t_env_map = try execution_mod.createNullDelimitedEnvMap(allocator, &env_map);
    defer execution_mod.freeEnvMap(allocator, null_t_env_map);

    var args = try argsWithAllocator(allocator);
    defer args.deinit();

    const program: [:0]const u8 = args.next().?;
    _ = program;
    const first_arg: ?([:0]const u8) = args.next();

    if (first_arg) |arg| {
        if (eql(u8, arg, "--m")) {
            try stdout_writer.print("Using manual parser\n", .{});
            try mainManualParser(stdout_writer, stdin_reader, stderr_writer, allocator, null_t_env_map);
        }
    } else {
        try mainBisonParser(stdout_writer, stdin_reader, stderr_writer, allocator, null_t_env_map);
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
