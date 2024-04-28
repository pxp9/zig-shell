const std = @import("std");

extern fn obtain_order(arg_argvvp: [*c][*c][*c][*c]u8, arg_filep: [*c][3]u8, arg_bgp: [*c]c_int) c_int;

const BisonParseError = error{ParseError};

pub fn parse(std_writer: anytype) !void {
    const zero_u8: u8 = 0;
    var filev: [3]*u8 = .{ @constCast(&zero_u8), @constCast(&zero_u8), @constCast(&zero_u8) };

    var arg_argvvp: [*c][*c][*c]u8 = null;
    var bg: c_int = 0;
    const returned_int: i32 = obtain_order(@ptrCast(&arg_argvvp), @ptrCast(&filev), @ptrCast(&bg));

    if (returned_int == -1) {
        return error.ParseError;
    }

    try std_writer.print("Returned int: {}\n", .{returned_int});
    try std_writer.print("{s}\n", .{arg_argvvp[0][0]});
}
