// Import the standard library and assign it to 'std'
const std = @import("std");

// Define a global variable to store the original terminal settings
// 'undefined' means we'll set its value later
var orig_termios: std.posix.termios = undefined;

// Function to restore the original terminal settings
fn disableRawMode() void {
    // Restore original terminal settings. We use 'catch {}' to ignore any errors
    std.posix.tcsetattr(std.io.getStdIn().handle, .FLUSH, orig_termios) catch {};
}

// Function to enable raw mode in the terminal, returns an error union
fn enableRawMode() !void {
    // Get the file handle for standard input
    const stdin = std.io.getStdIn().handle;

    // Get the current terminal settings and store them in orig_termios
    // 'try' is used for error handling - it returns the error if one occurs
    orig_termios = try std.posix.tcgetattr(stdin);

    // Create a new termios struct that we can modify
    var raw = orig_termios;

    // Disable terminal echo (characters won't show when typed)
    raw.lflag.ECHO = false;
    // Disable canonical mode (input is processed byte by byte, not line by line)
    raw.lflag.ICANON = false;
    // Disable signals like Ctrl-C and Ctrl-Z
    raw.lflag.ISIG = false;
    // Disable signals like Ctrl-S and Ctrl-Q
    raw.iflag.IXON = false;
    // Disable Ctrl-V signal
    raw.lflag.IEXTEN = false;
    // Fix Ctrl-M
    raw.iflag.ICRNL = false;
    // Turn off all output processing
    raw.oflag.OPOST = false;
    // BRKINT, INPCK, ISTRIP, Miscellaneous flags, TODO: remember to check the CS8 flag
    raw.iflag.BRKINT = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;

    // Apply our modified settings to the terminal
    try std.posix.tcsetattr(stdin, .FLUSH, raw);
}

// Main function that can return any error
pub fn main() anyerror!void {
    // Enable raw mode and handle potential errors
    try enableRawMode();
    // Ensure we disable raw mode when the program exits
    defer disableRawMode();

    // Create reader and writer objects for stdin and stdout
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    // Create a single-byte buffer for reading input
    var buf: [1]u8 = undefined;

    // Main program loop
    while (true) {
        // Read one byte from stdin into our buffer
        const n = try stdin.read(buf[0..]);
        // Exit if we didn't read exactly one byte or if 'q' was pressed
        if (n != 1 or buf[0] == 'q') break;

        // Check if the character is a control character (like newline, escape, etc)
        if (std.ascii.isControl(buf[0])) {
            // Print control characters as their numeric value
            try stdout.print("{d}\r\n", .{buf[0]});
        } else {
            // Print regular characters as both their numeric value and the character itself
            try stdout.print("{d} ('{c}')\r\n", .{ buf[0], buf[0] });
        }
    }
}
