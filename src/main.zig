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

//*** data ***/

const zilo_version = "0.0.1";

const EditorConfig = struct {
    screenrows: u16,
    screencols: u16,
    orig_termios: std.posix.termios,
};

var E = EditorConfig{
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

fn editorReadKey() !u8 {
    var buf: [1]u8 = undefined;
    const stdin = std.io.getStdIn().reader();

    while (true) {
        const n = try stdin.read(buf[0..]);
        if (n == 1) break;
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
    try writer.writeAll("\x1b[H");
    try writer.writeAll("\x1b[?25h");
    try std.io.getStdOut().writer().writeAll(buf.items);
}

fn editorDrawRows(writer: anytype) !void {
    var y: usize = 0;
    while (y < E.screenrows) : (y += 1) {
        if (y == E.screenrows / 3) {
            try writer.print("Zilo editor -- version {s}", .{zilo_version});
        } else {
            try writer.writeAll("~");
        }
        try writer.writeAll("\x1b[K");
        if (y < E.screenrows - 1) try writer.writeAll("\r\n");
    }
}

//*** input ***/
fn editorProcessKeypress() !KeyAction {
    const c = try editorReadKey();

    return switch (c) {
        CTRL_KEY('q') => {
            try std.io.getStdOut().writer().writeAll("\x1b[2J");
            try std.io.getStdOut().writer().writeAll("\x1b[H");
            return .Quit;
        }, // Now we clear the screen on quitting
        else => .NoOp, // All other keys do nothing (.NoOp = no operation)
    };
}

//*** init ***/
fn initEditor() void {
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
