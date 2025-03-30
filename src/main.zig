// Import the standard library and assign it to 'std'
const std = @import("std");

// Define a global variable to store the original terminal settings
// 'undefined' means we'll set its value later
var orig_termios: std.posix.termios = undefined;

// Function to restore the original terminal settings
fn disableRawMode() void {
    // Restore original terminal settings. We use 'catch {}' to ignore any errors
    std.posix.tcsetattr(std.io.getStdIn().handle, .FLUSH, orig_termios) catch {
        std.debug.print("Error: Failed to restore terminal settings\n", .{});
        std.process.exit(1);
    };
}

// Function to enable raw mode in the terminal, returns an error union
fn enableRawMode() !void {
    // Get the file handle for standard input
    const stdin = std.io.getStdIn().handle;

    // Get the current terminal settings and store them in orig_termios
    // 'try' is used for error handling - it returns the error if one occurs
    orig_termios = std.posix.tcgetattr(stdin) catch {
        std.debug.print("Error: Could not get terminal attributes\n", .{});
        return error.TerminalError;
    };

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
    // BRKINT, INPCK, ISTRIP, Miscellaneous flags
    raw.iflag.BRKINT = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;
    // Set 8 bit characters
    raw.cflag.CSIZE = .CS8;
    // Set read timeouts
    const VMIN = 5;
    const VTIME = 6;
    raw.cc[VMIN] = 0;
    raw.cc[VTIME] = 1;

    // Apply our modified settings to the terminal
    std.posix.tcsetattr(stdin, .FLUSH, raw) catch {
        std.debug.print("Error: Could not set terminal attributes\n", .{});
        return error.TerminalError;
    };
}

// Main function that can return any error
pub fn main() anyerror!void {
    // Enable raw mode and handle potential errors
    enableRawMode() catch {
        std.debug.print("Error: Failed to enter raw mode\n", .{});
        std.process.exit(1);
    };
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
        const n = stdin.read(buf[0..]) catch {
            std.debug.print("Error: Failed to read from stdin\n", .{});
            std.process.exit(1);
        };

        // Exit if we didn't read exactly one byte
        if (n != 1) break;

        // Check if the character is a control character (like newline, escape, etc)
        if (std.ascii.isControl(buf[0])) {
            stdout.print("{d}\r\n", .{buf[0]}) catch {
                std.debug.print("Error: Failed to write to stdout\n", .{});
                std.process.exit(1);
            };
        } else {
            stdout.print("{d} ('{c}')\r\n", .{ buf[0], buf[0] }) catch {
                std.debug.print("Error: Failed to write to stdout\n", .{});
                std.process.exit(1);
            };
        }

        // Exit if 'q' was pressed
        if (buf[0] == 'q') break;
    }
}
