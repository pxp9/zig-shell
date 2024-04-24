const std = @import("std");
const parser_mod = @import("parser.zig");
const ArrayList = std.ArrayList;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

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

    try stdout_writer.print("Run `zig build test` to run the tests.\n", .{});

    const parser = parser_mod.Parser.init(allocator);

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
