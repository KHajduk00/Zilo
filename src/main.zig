//*** includes ***/
const std = @import("std");

//*** data ***/
var orig_termios: std.posix.termios = undefined;

//*** terminal ***/
// Function to restore the original terminal settings
// Will print error and exit if restoration fails
fn disableRawMode() void {
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

//*** init ***/
// Main function that handles program execution and error handling
pub fn main() anyerror!void {
    enableRawMode() catch {
        std.debug.print("Error: Failed to enter raw mode\n", .{});
        std.process.exit(1);
    };
    defer disableRawMode();

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    var buf: [1]u8 = undefined;

    while (true) {
        const n = stdin.read(buf[0..]) catch {
            std.debug.print("Error: Failed to read from stdin\n", .{});
            std.process.exit(1);
        };

        if (n != 1) break;

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

        if (buf[0] == 'q') break;
    }
}
