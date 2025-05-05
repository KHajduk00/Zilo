//*** includes ***/
const std = @import("std");
const clib = @cImport({
    @cInclude("sys/ioctl.h");
    @cInclude("unistd.h");
});
const heap = @import("std").heap;
const mem = @import("std").mem;

//*** defines ***//
// Function to handle Ctrl key combinations
fn CTRL_KEY(comptime k: u8) u8 {
    return k & 0x1f;
}

const editorKey = enum(u16) {
    ARROW_LEFT = 'a',
    ARROW_RIGHT = 'd',
    ARROW_UP = 'w',
    ARROW_DOWN = 's',
    PAGE_UP = 0x1000,
    PAGE_DOWN = 0x1001,
};

//*** data ***/

const zilo_version = "0.0.1";

const EditorConfig = struct {
    cx: c_int,
    cy: c_int,

    screenrows: u16,
    screencols: u16,
    orig_termios: std.posix.termios,
};

var E = EditorConfig{
    .cx = undefined,
    .cy = undefined,

    .screenrows = undefined,
    .screencols = undefined,
    .orig_termios = undefined,
};

const KeyAction = enum {
    Quit,
    NoOp,
};

//*** terminal ***/
// Function to restore the original terminal settings
// Will print error and exit if restoration fails
export fn disableRawMode() void {
    std.posix.tcsetattr(std.io.getStdIn().handle, .FLUSH, E.orig_termios) catch {
        std.debug.print("Error: Failed to restore terminal settings\n", .{});
        std.process.exit(1);
    };
}

fn die(msg: []const u8) noreturn {
    std.io.getStdOut().writer().writeAll("\x1b[2J") catch {};
    std.io.getStdOut().writer().writeAll("\x1b[H") catch {};
    std.debug.print("Error: {s}\n", .{msg});

    std.process.exit(1);
}

// Function to enable raw mode in the terminal
// Returns an error if terminal settings cannot be configured
fn enableRawMode() !void {
    const stdin = std.io.getStdIn().handle;

    E.orig_termios = std.posix.tcgetattr(stdin) catch {
        std.debug.print("Error: Could not get terminal attributes\n", .{});
        return error.TerminalError;
    };

    var raw = E.orig_termios;

    // Terminal mode flags:
    raw.lflag.ECHO = false; // Don't echo input characters
    raw.lflag.ICANON = false; // Read input byte-by-byte instead of line-by-line
    raw.lflag.ISIG = false; // Disable Ctrl-C and Ctrl-Z signals
    raw.iflag.IXON = false; // Disable Ctrl-S and Ctrl-Q signals
    raw.lflag.IEXTEN = false; // Disable Ctrl-V
    raw.iflag.ICRNL = false; // Fix Ctrl-M
    raw.oflag.OPOST = false; // Disable output processing
    raw.iflag.BRKINT = false; // Disable break processing
    raw.iflag.INPCK = false; // Disable parity checking
    raw.iflag.ISTRIP = false; // Disable stripping of 8th bit
    raw.cflag.CSIZE = .CS8; // Use 8-bit characters

    // Set read timeouts
    const VMIN = 5; // Minimum number of bytes before read returns
    const VTIME = 6; // Time to wait for input (tenths of seconds)
    raw.cc[VMIN] = 0; // Return immediately when any bytes are available
    raw.cc[VTIME] = 1; // Wait up to 0.1 seconds for input

    std.posix.tcsetattr(stdin, .FLUSH, raw) catch {
        std.debug.print("Error: Could not set terminal attributes\n", .{});
        return error.TerminalError;
    };
}

fn editorReadKey() !u16 {
    var buf: [1]u8 = undefined;
    const stdin = std.io.getStdIn().reader();

    while (true) {
        const n = try stdin.read(buf[0..]);
        if (n == 1) break;
    }

    // Read escape sequence
    if (buf[0] == '\x1b') {
        var seq: [3]u8 = undefined;

        // Read first character of sequence
        const seq1 = try stdin.read(seq[0..1]);
        if (seq1 != 1) return '\x1b';

        if (seq[0] == '[') {
            // Read second character
            const seq2 = try stdin.read(seq[1..2]);
            if (seq2 != 1) return '\x1b';

            if (seq[1] >= '0' and seq[1] <= '9') {
                // Read third character for extended sequences
                const seq3 = try stdin.read(seq[2..3]);
                if (seq3 != 1) return '\x1b';

                if (seq[2] == '~') {
                    // Handle Page Up/Down
                    return switch (seq[1]) {
                        '5' => @intFromEnum(editorKey.PAGE_UP),
                        '6' => @intFromEnum(editorKey.PAGE_DOWN),
                        else => '\x1b',
                    };
                }
            } else {
                // Handle arrow keys
                return switch (seq[1]) {
                    'A' => @intFromEnum(editorKey.ARROW_UP),
                    'B' => @intFromEnum(editorKey.ARROW_DOWN),
                    'C' => @intFromEnum(editorKey.ARROW_RIGHT),
                    'D' => @intFromEnum(editorKey.ARROW_LEFT),
                    else => '\x1b',
                };
            }
        }
        return '\x1b';
    }
    return buf[0];
}

fn getWindowSize(rows: *u16, cols: *u16) c_int {
    var ws: clib.winsize = undefined;

    if (clib.ioctl(clib.STDOUT_FILENO, clib.TIOCGWINSZ, &ws) == -1 or ws.ws_col == 0) {
        return -1;
    } else {
        cols.* = ws.ws_col;
        rows.* = ws.ws_row;
        return 0;
    }
}

//*** output ***/
fn editorRefreshScreen(allocator: mem.Allocator) !void {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    var writer = buf.writer();

    try writer.writeAll("\x1b[?25l");
    try writer.writeAll("\x1b[H");

    try editorDrawRows(writer);
    try writer.print("\x1b[{d};{d}H", .{ E.cy + 1, E.cx + 1 });

    try writer.writeAll("\x1b[?25h");
    try std.io.getStdOut().writer().writeAll(buf.items);
}

fn editorDrawRows(writer: anytype) !void {
    var y: usize = 0;
    while (y < E.screenrows) : (y += 1) {
        if (y == E.screenrows / 3) {
            // Create welcome message
            var welcome: [80]u8 = undefined;
            const welcome_msg = try std.fmt.bufPrint(&welcome, "Zilo editor -- version {s}", .{zilo_version});

            // Handle message that might be too wide
            const display_len = @min(welcome_msg.len, E.screencols);
            const padding = (E.screencols - display_len) / 2;

            // Add left padding with space
            var i: usize = 0;
            while (i < padding) : (i += 1) {
                try writer.writeAll(" ");
            }

            // Print the message
            try writer.writeAll(welcome_msg[0..display_len]);
        } else {
            // For other lines, just print a single '~' at the start
            try writer.writeAll("~");
        }

        // Clear to end of line and add newline (except last line)
        try writer.writeAll("\x1b[K");
        if (y < E.screenrows - 1) {
            try writer.writeAll("\r\n");
        }
    }
}

//*** input ***/
fn editorMoveCursor(key: u16) void {
    switch (key) {
        @intFromEnum(editorKey.ARROW_LEFT) => if (E.cx != 0) {
            E.cx -= 1;
        },
        @intFromEnum(editorKey.ARROW_RIGHT) => if (E.cx != E.screencols - 1) {
            E.cx += 1;
        },
        @intFromEnum(editorKey.ARROW_UP) => if (E.cy != 0) {
            E.cy -= 1;
        },
        @intFromEnum(editorKey.ARROW_DOWN) => if (E.cy != E.screenrows - 1) {
            E.cy += 1;
        },
        else => {},
    }
}

fn editorProcessKeypress() !KeyAction {
    const c = try editorReadKey();

    return switch (c) {
        CTRL_KEY('q') => {
            try std.io.getStdOut().writer().writeAll("\x1b[2J");
            try std.io.getStdOut().writer().writeAll("\x1b[H");
            return .Quit;
        },
        @intFromEnum(editorKey.PAGE_UP) => .NoOp,
        @intFromEnum(editorKey.PAGE_DOWN) => .NoOp,
        @intFromEnum(editorKey.ARROW_UP), @intFromEnum(editorKey.ARROW_DOWN), @intFromEnum(editorKey.ARROW_LEFT), @intFromEnum(editorKey.ARROW_RIGHT) => {
            editorMoveCursor(c);
            return .NoOp;
        },
        else => .NoOp,
    };
}

//*** init ***/
fn initEditor() void {
    E.cx = 0;
    E.cy = 0;

    if (getWindowSize(&E.screenrows, &E.screencols) == -1) {
        die("getWindowSize");
    }
}

pub fn main() anyerror!void {
    // Set up an arena allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try enableRawMode();
    defer disableRawMode();
    initEditor();

    while (true) {
        try editorRefreshScreen(allocator);
        switch (try editorProcessKeypress()) {
            .Quit => break,
            else => {},
        }
    }
}
