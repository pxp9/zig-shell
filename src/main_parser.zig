const std = @import("std");
const tokenizer_mod = @import("parser/tokenizer.zig");

const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const MAX_FILE_SIZE: usize = 1024;
const ArrayList = std.ArrayList;
const Tokenizer = tokenizer_mod.Tokenizer;
const Token = tokenizer_mod.Token;
const Tag = tokenizer_mod.Tag;

const cwd = std.fs.cwd;
const next = tokenizer_mod.next;

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

    _ = stderr_writer;

    try stdout_writer.print("\nWelcome to the Zig Shell.\n", .{});

    const file = try cwd().openFile("test_parser/hello.sh", .{ .mode = .read_only });
    defer file.close();

    const pos = try file.getEndPos();
    const arr: [:0]const u8 = try allocator.allocSentinel(u8, @intCast(pos), 0);
    defer allocator.free(arr);

    const to_parse = ArrayList(u8).init(allocator);
    defer to_parse.deinit();

    _ = try file.read(@constCast(@ptrCast(arr)));

    try stdout_writer.print("File contents: \"{s}\"\n", .{arr});

    const tokenizer = Tokenizer(Token).init(arr);

    var token = next(@constCast(&tokenizer));

    while (token.tag != Tag.EOF) {
        try stdout_writer.print("Token: {s}, Type : {any}\n", .{ arr[token.loc.start..token.loc.end], token.tag });
        token = next(@constCast(&tokenizer));
    }

    try stdout_writer.print("Write some valid syntax\n> ", .{});

    // here is when we block on reading from stdin until we got new commands
    try stdin_reader.streamUntilDelimiter(@constCast(&to_parse).writer(), '\n', null);

    const arr2: [:0]u8 = try @constCast(&to_parse).toOwnedSliceSentinel(0);
    defer allocator.free(arr2);

    const tokenizer2 = Tokenizer(Token).init(arr2);

    token = next(@constCast(&tokenizer2));

    while (token.tag != Tag.EOF) {
        try stdout_writer.print("Token: {s}, Type : {any}\n", .{ arr2[token.loc.start..token.loc.end], token.tag });
        token = next(@constCast(&tokenizer2));
    }
}
