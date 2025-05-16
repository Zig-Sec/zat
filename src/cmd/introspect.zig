const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;
const process = std.process;
const fatal = process.fatal;

const misc = @import("../misc.zig");

pub const Build = @import("introspect/Build.zig");

const build_string = @embedFile("introspect/Build.zig");

pub fn cmdIntrospect(
    allocator: Allocator,
    arena: Allocator,
    args: anytype,
) !void {
    _ = arena;
    _ = args;

    const build_root = misc.findBuildRoot(allocator, .{}) catch |e| {
        fatal("unable to determine build root ({any})", .{e});
    };

    const build_zig_modified = try readAndModifyBuildZig(build_root.directory.handle, allocator);
    defer allocator.free(build_zig_modified);

    std.debug.print("{s}\n", .{build_zig_modified});
}

fn readAndModifyBuildZig(root_dir: fs.Dir, allocator: Allocator) ![]const u8 {
    const fbuild_zig = try root_dir.openFile("build.zig", .{});
    defer fbuild_zig.close();

    const content = try fbuild_zig.readToEndAlloc(allocator, 50_000_000);
    defer allocator.free(content);

    const modified = try std.mem.replaceOwned(u8, allocator, content, "std.Build", "zat.Build");

    var al = std.ArrayList(u8).fromOwnedSlice(allocator, modified);
    errdefer al.deinit();

    try al.writer().print(
        \\
        \\//---------------------------------
        \\// Zig Audit Tool (ZAT)
        \\//---------------------------------
        \\
        \\{s}
    ,
        .{build_string},
    );

    return try al.toOwnedSlice();
}

test {
    _ = Build;
}
