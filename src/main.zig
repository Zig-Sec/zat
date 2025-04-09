const std = @import("std");
const clap = @import("clap");

const root = @import("root.zig");

const stdin = std.io.getStdIn();
const stdout = std.io.getStdOut();
const stderr = std.io.getStdErr();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var arena_instance = std.heap.ArenaAllocator.init(allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help               Display this help and exit.
        \\--audit                  Audit a package
        \\--release                Create a new release for a package
        \\--graph                  Create a dependency graph
        \\--major                  Major release
        \\--minor                  Minor release
        \\--patch                  Patch release
        \\-y                       Accept all changes
        \\--mermaid                Use the mermaid format
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return;
    };
    defer res.deinit();

    if (res.args.audit != 0) {
        try root.audit.cmdAudit(allocator, arena, res.args);
    } else if (res.args.release != 0) {
        try root.release.cmdNewRelease(allocator, arena, res.args);
    } else if (res.args.graph != 0) {
        try root.graph.cmdGraph(allocator, arena, res.args);
    } else {
        try std.fmt.format(stdout.writer(), help_text, .{});
        return;
    }
}

pub fn openFolder(path: []const u8) !std.fs.Dir {
    return if (path.len >= 2 and path[0] == '~' and path[1] == '/') blk: {
        const home = std.c.getenv("HOME");
        if (home == null) return error.NoHome;
        var home_dir = try std.fs.openDirAbsolute(home.?[0..std.zig.c_builtins.__builtin_strlen(home.?)], .{});
        defer home_dir.close();
        break :blk try home_dir.openDir(path[2..], .{});
    } else if (path.len >= 1 and path[0] == '/') blk: {
        break :blk try std.fs.openDirAbsolute(path[0..], .{});
    } else blk: {
        break :blk try std.fs.cwd().openDir(path[0..], .{});
    };
}

pub fn createFile(path: []const u8) !std.fs.File {
    return if (path[0] == '~' and path[1] == '/') blk: {
        const home = std.c.getenv("HOME");
        if (home == null) return error.NoHome;
        var home_dir = try std.fs.openDirAbsolute(home.?[0..std.zig.c_builtins.__builtin_strlen(home.?)], .{});
        defer home_dir.close();
        const file = try home_dir.createFile(path[2..], .{
            .exclusive = true,
        });
        break :blk file;
    } else if (path[0] == '/') blk: {
        const file = try std.fs.createFileAbsolute(path[0..], .{
            .exclusive = true,
        });
        break :blk file;
    } else blk: {
        const file = try std.fs.cwd().createFile(path[0..], .{
            .exclusive = true,
        });
        break :blk file;
    };
}

const help_text =
    \\zat - Zig Audit Tool
    \\Copyright (C) 2025 Zig-Sec org. (https://github.com/Zig-Sec)
    \\Authors:
    \\ David P. Sugar (r4gus)
    \\License MIT <https://opensource.org/license/MIT>
    \\This is free software: you are free to change and redistribute it.
    \\There is NO WARRANTY, to the extent permitted by law.
    \\
    \\Syntax: zat [options]
    \\
    \\Commands:
    \\ -h, --help                                  Display this help and exit.
    \\ --release                                   Create a new release
    \\ --graph                                     Create a dependency graph
    \\
    \\Options:
    \\ -y                                          Accept all
    \\
    \\Release Options
    \\ --major                                     Create a major release
    \\ --minor                                     Create a minor release
    \\ --patch                                     Create a patch release
    \\
    \\Graph Options
    \\ --mermaid                                   Create a mermaid graph
    \\
;
