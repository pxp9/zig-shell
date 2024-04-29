const std = @import("std");

pub fn Tokenizer(comptime Tok: type) type {
    return struct {
        buffer: [:0]const u8,
        index: usize,
        pending_invalid_token: ?Tok,

        const Self = Tokenizer(Tok);

        pub fn init(buffer: [:0]const u8) Self {
            // Skip the UTF-8 BOM if present
            const src_start: usize = if (std.mem.startsWith(u8, buffer, "\xEF\xBB\xBF")) 3 else 0;
            return Self{
                .buffer = buffer,
                .index = src_start,
                .pending_invalid_token = null,
            };
        }
    };
}

pub const Tag = enum {
    EOF,
    Identifier,
    Arg,
    Pipe,
    StringDoubleQuote,
    StringSingleQuote,
    Background,
    RedirectionStdout,
    RedirectionStderr,
    RedirectionSdtin,
    Invalid,
};

pub const Loc = struct {
    start: usize,
    end: usize,
};

pub const Token = struct {
    tag: Tag,
    loc: Loc,
};

const State = enum {
    Start,
    Identifier,
    Arg,
    StringDoubleQuote,
    StringSingleQuote,
    Redir,
};

pub fn next(self: *Tokenizer(Token)) Token {
    if (self.pending_invalid_token) |token| {
        self.pending_invalid_token = null;
        return token;
    }
    var state: State = .Start;
    var result = Token{
        .tag = .EOF,
        .loc = .{
            .start = self.index,
            .end = undefined,
        },
    };

    while (true) : (self.index += 1) {
        const c = self.buffer[self.index];

        switch (state) {
            .Start => {
                switch (c) {
                    0 => {
                        if (self.index != self.buffer.len) {
                            result.tag = .Invalid;
                            result.loc.start = self.index;
                            self.index += 1;
                            result.loc.end = self.index;
                            return result;
                        }
                        break;
                    },

                    ' ', '\n', '\t', '\r' => {
                        result.loc.start = self.index + 1;
                    },

                    '"' => {
                        state = .StringDoubleQuote;
                        result.tag = .StringDoubleQuote;
                    },

                    '\'' => {
                        state = .StringSingleQuote;
                        result.tag = .StringSingleQuote;
                    },

                    'a'...'z', 'A'...'Z', '_' => {
                        state = .Identifier;
                        result.tag = .Identifier;
                    },
                    '|' => {
                        result.tag = .Pipe;
                        self.index += 1;
                        break;
                    },
                    '-' => {
                        state = .Arg;
                        result.tag = .Arg;
                    },

                    '<' => {
                        result.tag = .RedirectionSdtin;
                        self.index += 1;
                        break;
                    },

                    '>' => {
                        state = .Redir;
                    },

                    '&' => {
                        result.tag = .Background;
                        self.index += 1;
                        break;
                    },
                    else => {
                        result.tag = .Invalid;
                        result.loc.end = self.index;
                        self.index += 1;
                        return result;
                    },
                }
            },

            .Identifier => {
                switch (c) {
                    'a'...'z', 'A'...'Z', '0'...'9', '_', '.' => {},
                    else => {
                        break;
                    },
                }
            },

            .Arg => {
                switch (c) {
                    'a'...'z', 'A'...'Z', '0'...'9', '=', '-', '.' => {},
                    else => {
                        break;
                    },
                }
            },

            .Redir => {
                switch (c) {
                    '&' => {
                        result.tag = .RedirectionStderr;
                        self.index += 1;
                        break;
                    },
                    else => {
                        result.tag = .RedirectionStdout;
                        break;
                    },
                }
            },
            .StringDoubleQuote => {
                switch (c) {
                    '"' => {
                        self.index += 1;
                        break;
                    },
                    0 => {
                        if (self.index == self.buffer.len) {
                            result.tag = .Invalid;
                            break;
                        } else {
                            checkLiteralCharacter(self);
                        }
                    },
                    '\n' => {
                        result.tag = .Invalid;
                        break;
                    },
                    else => checkLiteralCharacter(self),
                }
            },
            .StringSingleQuote => {
                switch (c) {
                    '\'' => {
                        self.index += 1;
                        break;
                    },
                    0 => {
                        if (self.index == self.buffer.len) {
                            result.tag = .Invalid;
                            break;
                        } else {
                            checkLiteralCharacter(self);
                        }
                    },
                    '\n' => {
                        result.tag = .Invalid;
                        break;
                    },
                    else => checkLiteralCharacter(self),
                }
            },
        }
    }

    if (result.tag == .EOF) {
        if (self.pending_invalid_token) |token| {
            self.pending_invalid_token = null;
            return token;
        }
        result.loc.start = self.index;
    }

    result.loc.end = self.index;
    return result;
}

fn checkLiteralCharacter(self: *Tokenizer(Token)) void {
    if (self.pending_invalid_token != null) return;
    const invalid_length = getInvalidCharacterLength(self);
    if (invalid_length == 0) return;
    self.pending_invalid_token = .{
        .tag = .Invalid,
        .loc = .{
            .start = self.index,
            .end = self.index + invalid_length,
        },
    };
}

fn getInvalidCharacterLength(self: *Tokenizer(Token)) u3 {
    const c0 = self.buffer[self.index];
    if (std.ascii.isASCII(c0)) {
        if (c0 == '\r') {
            if (self.index + 1 < self.buffer.len and self.buffer[self.index + 1] == '\n') {
                // Carriage returns are *only* allowed just before a linefeed as part of a CRLF pair, otherwise
                // they constitute an illegal byte!
                return 0;
            } else {
                return 1;
            }
        } else if (std.ascii.isControl(c0)) {
            // ascii control codes are never allowed
            // (note that \n was checked before we got here)
            return 1;
        }
        // looks fine to me.
        return 0;
    } else {
        // check utf8-encoded character.
        const length = std.unicode.utf8ByteSequenceLength(c0) catch return 1;
        if (self.index + length > self.buffer.len) {
            return @as(u3, @intCast(self.buffer.len - self.index));
        }
        const bytes = self.buffer[self.index .. self.index + length];
        switch (length) {
            2 => {
                const value = std.unicode.utf8Decode2(bytes) catch return length;
                if (value == 0x85) return length; // U+0085 (NEL)
            },
            3 => {
                const value = std.unicode.utf8Decode3(bytes) catch return length;
                if (value == 0x2028) return length; // U+2028 (LS)
                if (value == 0x2029) return length; // U+2029 (PS)
            },
            4 => {
                _ = std.unicode.utf8Decode4(bytes) catch return length;
            },
            else => unreachable,
        }
        self.index += length - 1;
        return 0;
    }
}
