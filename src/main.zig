const std = @import("std");

//Global vars:
var orig_termios: std.posix.termios = undefined;

fn disableRawMode() void {
    std.posix.tcsetattr(std.io.getStdIn().handle, .FLUSH, orig_termios) catch {};
}

fn enableRawMode() !void {
    const stdin = std.io.getStdIn().handle;

    // Store the original terminal state
    orig_termios = try std.posix.tcgetattr(stdin);

    // Create a mutable copy of the original termios
    var raw = orig_termios;

    // Disable echoing and other flags for raw mode
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;

    // Apply the modified terminal settings
    try std.posix.tcsetattr(stdin, .FLUSH, raw);
}

pub fn main() anyerror!void {
    try enableRawMode();

    defer disableRawMode();

    const stdin = std.io.getStdIn().reader();
    var buf: [1]u8 = undefined;
    while (true) {
        const n = try stdin.read(buf[0..]);
        if (n != 1 or buf[0] == 'q') break;
    }
}
