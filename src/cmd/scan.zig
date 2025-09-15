const std = @import("std");
const Allocator = std.mem.Allocator;
const fatal = std.process.fatal;

const CodeScanner = @import("../CodeScanner.zig");

pub fn cmdScan(
    allocator: Allocator,
    arena: Allocator,
    args: anytype,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !void {
    _ = arena;
    _ = args;
    _ = stdout;
    _ = stderr;

    // TODO: let the user decide
    const cwd = std.fs.cwd();

    // TODO: let the user decide
    const p = "src/root.zig";

    var scanner = CodeScanner.init(allocator, cwd, p);

    _ = try scanner.findFunc("init", .{});
}
