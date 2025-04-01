//*** includes ***/
const std = @import("std");

//*** defines ***//
// Function to handle Ctrl key combinations
fn CTRL_KEY(comptime k: u8) u8 {
    return k & 0x1f;
}

//*** data ***/
var orig_termios: std.posix.termios = undefined;

const KeyAction = enum {
    Quit,
    NoOp,
};

//*** terminal ***/
// Function to restore the original terminal settings
// Will print error and exit if restoration fails
export fn disableRawMode() void {
    std.posix.tcsetattr(std.io.getStdIn().handle, .FLUSH, orig_termios) catch {
        std.debug.print("Error: Failed to restore terminal settings\n", .{});
        std.process.exit(1);
    };
}

// Function to enable raw mode in the terminal
// Returns an error if terminal settings cannot be configured
fn enableRawMode() !void {
    const stdin = std.io.getStdIn().handle;

    orig_termios = std.posix.tcgetattr(stdin) catch {
        std.debug.print("Error: Could not get terminal attributes\n", .{});
        return error.TerminalError;
    };

    var raw = orig_termios;

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

//*** output ***/
fn editorRefreshScreen() !void {
    try std.io.getStdOut().writer().writeAll("\x1b[2J");
}

//*** input ***/
fn editorProcessKeypress() !KeyAction {
    const c = try editorReadKey();

    return switch (c) {
        CTRL_KEY('q') => .Quit, // This quits
        else => .NoOp, // All other keys do nothing (.NoOp = no operation)
    };
}

//*** init ***/
pub fn main() anyerror!void {
    try enableRawMode();
    defer disableRawMode();

    while (true) {
        try editorRefreshScreen();
        switch (try editorProcessKeypress()) {
            .Quit => break,
            else => {},
        }
    }
}
