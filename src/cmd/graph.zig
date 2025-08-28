const std = @import("std");
const Allocator = std.mem.Allocator;

const Fetch = @import("../Fetch.zig");
const PackageInfo = @import("../PackageInfo.zig");
const DepMap = PackageInfo.Map;

const misc = @import("../misc.zig");

const Format = enum {
    mermaid,
};

pub fn cmdGraph(
    allocator: Allocator,
    arena: Allocator,
    args: anytype,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !void {
    _ = stderr;

    var f: ?std.fs.File = null;
    defer if (f) |f_| f_.close();
    var fw: ?std.fs.File.Writer = null;

    var root_prog_node = std.Progress.start(.{
        .root_name = "generate graph",
    });

    var writer = if (args.path) |path| blk: {
        f = try misc.createFile(path, .{});
        fw = f.?.writer(&.{});
        break :blk &fw.?.interface;
    } else blk: {
        break :blk stdout;
    };

    const root, var map = try Fetch.fetchPackageDependencies(
        allocator,
        arena,
        root_prog_node,
    );
    defer {
        var iter = map.iterator();
        while (iter.next()) |dep| dep.value_ptr.deinit(allocator);
        map.deinit();
    }

    try map.put(try allocator.dupe(u8, root.ref), root);

    const format: Format = if (args.mermaid != 0) blk: {
        break :blk .mermaid;
    } else blk: {
        break :blk .mermaid;
    };

    root_prog_node.end();

    switch (format) {
        .mermaid => {
            try writer.writeAll("%%{init: {\"flowchart\": {\"htmlLabels\": false}} }%%\n");
            try writer.writeAll("graph TD;\n");

            var iter = map.iterator();
            while (iter.next()) |dep| {
                try dep.value_ptr.printMermaid(writer);

                for (dep.value_ptr.children.items) |child| {
                    try writer.print("    {x} --> {x}\n", .{
                        &dep.value_ptr.sha256HashFromRef(),
                        &PackageInfo.hashFromRef(child),
                    });
                }
            }
        },
    }
}
