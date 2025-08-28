const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

pub const injected = @import("InspectBuild/injected.zig");

/// The code to be injected into a `build.zig` as raw string.
const injectable_code = @embedFile("InspectBuild/injected.zig");

pub fn inspect(build_root: std.fs.Dir, allocator: Allocator) !injected.zat.Components {
    try readAndModifyBuildZig(build_root, allocator);

    const info = std.process.Child.run(.{
        .allocator = allocator,
        .cwd_dir = build_root,
        .argv = &.{
            "zig",
            "build",
            "-h", // this way build zig only generates the build graph...
        },
    }) catch |e| {
        std.log.err("unable to execute 'zig build -h' ({any})", .{e});
        restoreBuildZig(build_root, allocator) catch |e2| {
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
                const json = info.stdout[0..index];
                const comps = std.json.parseFromSliceLeaky(
                    injected.zat.Components,
                    allocator,
                    json,
                    .{
                        .allocate = .alloc_always,
                    },
                ) catch |e| {
                    std.log.err("unable to parse json ({any})", .{e});
                    restoreBuildZig(build_root, allocator) catch |e2| {
                        std.log.err("unable to restore 'build.zig' ({any})", .{e2});
                        return e;
                    };
                    return e;
                };

                restoreBuildZig(build_root, allocator) catch |e| {
                    std.log.err("unable to restore 'build.zig' ({any})", .{e});
                    return e;
                };

                return comps;
            }
        },
        else => {
            std.log.err("'build.zig' inspection failed. This is probably due to a corrupted 'build.zig' which is the result of the modification made to the file.\nOriginal error:\n{s}", .{info.stderr[0..]});

            restoreBuildZig(build_root, allocator) catch |e| {
                std.log.err("unable to restore 'build.zig' ({any})", .{e});
                return e;
            };
        },
    }

    restoreBuildZig(build_root, allocator) catch |e| {
        std.log.err("unable to restore 'build.zig' ({any})", .{e});
        return e;
    };

    return error.Inspection;
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
    const modified = try std.mem.replaceOwned(u8, allocator, content, "fn build(", "fn buil_(");

    const fun_opening = "pub fn build(b: *std.Build) !void {";
    const fun_closing =
        \\    var zat_stdout_buffer: [1024]u8 = undefined;
        \\    var zat_stdout_writer = std_zat_.fs.File.stdout().writer(&zat_stdout_buffer);
        \\    const zat_stdout = &zat_stdout_writer.interface;
        \\
        \\    const components = try zat.Components.fromBuild(b);
        \\    const comp_json = try std_zat_.json.Stringify.valueAlloc(
        \\        b.allocator,
        \\        components,
        \\        .{
        \\            .whitespace = .indent_2,
        \\            .emit_null_optional_fields = false,
        \\        },
        \\    );
        \\    try zat_stdout.writeAll(comp_json);
        \\    try zat_stdout.writeAll("\n");
        \\}
    ;

    // TODO: check zig version and adjust modifications
    try fbuild_zig.seekTo(0);
    var w = fbuild_zig.writer(&.{});
    try w.interface.print(
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
            injectable_code,
        },
    );
}

test {
    _ = injected;
}
