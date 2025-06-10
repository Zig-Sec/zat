const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;
const process = std.process;
const fatal = process.fatal;

const misc = @import("../misc.zig");

const injected = @import("introspect/injected.zig");

const build_code = @embedFile("introspect/injected.zig");

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

    try readAndModifyBuildZig(build_root.directory.handle, allocator);

    const info = std.process.Child.run(.{
        .allocator = allocator,
        .cwd_dir = build_root.directory.handle,
        .argv = &.{
            "zig",
            "build",
            "-h", // this way build zig only generates the build graph...
        },
    }) catch |e| {
        std.log.err("unable to execute 'zig build -h' ({any})", .{e});
        restoreBuildZig(build_root.directory.handle, allocator) catch |e2| {
            std.log.err("unable to restore 'build.zig' ({any})", .{e2});
            return e;
        };
        return e;
    };
    defer {
        allocator.free(info.stdout);
        allocator.free(info.stderr);
    }

    switch (info.term.Exited) {
        0 => {
            if (std.mem.indexOf(u8, info.stdout, "Usage")) |index| {
                std.io.getStdOut().writer().print("{s}\n", .{info.stdout[0..index]}) catch {
                    restoreBuildZig(build_root.directory.handle, allocator) catch |e| {
                        std.log.err("unable to restore 'build.zig' ({any})", .{e});
                        return e;
                    };
                };
            }
        },
        else => {
            std.log.err("'build.zig' introspection failed. This is probably due to a corrupted 'build.zig' which is the result of the modification made to the file.\nOriginal error:\n{s}", .{info.stderr[0..]});
        },
    }

    restoreBuildZig(build_root.directory.handle, allocator) catch |e| {
        std.log.err("unable to restore 'build.zig' ({any})", .{e});
        return e;
    };
}

fn restoreBuildZig(root_dir: fs.Dir, allocator: Allocator) !void {
    const backup = try root_dir.openFile("build.zig.zat", .{});
    const bz = try root_dir.createFile("build.zig", .{ .truncate = true });

    const content = try backup.readToEndAlloc(allocator, 50_000_000);
    defer allocator.free(content);

    try bz.writeAll(content);
}

fn readAndModifyBuildZig(root_dir: fs.Dir, allocator: Allocator) !void {
    const fbuild_zig = try root_dir.openFile("build.zig", .{
        .mode = .read_write,
    });
    defer fbuild_zig.close();

    const content = try fbuild_zig.readToEndAlloc(allocator, 50_000_000);
    defer allocator.free(content);

    // Duplicate
    const backup = try root_dir.createFile("build.zig.zat", .{});
    try backup.writeAll(content);

    // Modify
    const modified = try std.mem.replaceOwned(u8, allocator, content, "fn build", "fn buil_");

    const fun_opening = "pub fn build(b: *std.Build) !void {";
    const fun_closing =
        \\    const components = try zat.Components.fromBuild(b);
        \\    const comp_json = try std_zat_.json.stringifyAlloc(
        \\        b.allocator,
        \\        components,
        \\        .{
        \\            .whitespace = .indent_2,
        \\            .emit_null_optional_fields = false,
        \\        },
        \\    );
        \\    try std_zat_.io.getStdOut().writeAll(comp_json);
        \\    try std_zat_.io.getStdOut().writeAll("\n");
        \\}
    ;

    // TODO: check zig version and adjust modifications
    try fbuild_zig.seekTo(0);
    try fbuild_zig.writer().print(
        \\{s}
        \\
        \\//---------------------------------
        \\// Zig Audit Tool (ZAT)
        \\//---------------------------------
        \\
        \\{s}
        \\{s}
        \\{s}
        \\
        \\{s}
    ,
        .{
            modified,
            fun_opening,
            if (std.mem.containsAtLeast(u8, content, 1, "build(b: *std.Build) !void")) "try buil_(b);" else "buil_(b);",
            fun_closing,
            build_code,
        },
    );

    //var al = std.ArrayList(u8).fromOwnedSlice(allocator, modified);
    //errdefer al.deinit();

    //try al.writer().print(
    //    \\
    //    \\//---------------------------------
    //    \\// Zig Audit Tool (ZAT)
    //    \\//---------------------------------
    //    \\
    //    \\{s}
    //    \\{s}
    //,
    //    .{ build_function, build_code },
    //);

    //return try al.toOwnedSlice();
}

test {
    _ = injected;
}
