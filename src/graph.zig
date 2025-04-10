const std = @import("std");
const Allocator = std.mem.Allocator;

const PackageInfo = @import("PackageInfo.zig");
const DepMap = PackageInfo.PackageInfoMap;

const audit = @import("audit.zig");

const misc = @import("misc.zig");

const Format = enum {
    mermaid,
};

pub fn cmdGraph(
    allocator: Allocator,
    arena: Allocator,
    args: anytype,
) !void {
    var f: ?std.fs.File = null;
    defer if (f) |f_| f_.close();

    var root_prog_node = std.Progress.start(.{
        .root_name = "generate graph",
    });
    defer root_prog_node.end();

    var writer = if (args.path) |path| blk: {
        f = try misc.createFile(path, .{});
        break :blk f.?.writer();
    } else blk: {
        break :blk std.io.getStdOut().writer();
    };

    const root, var map = try audit.fetchPackageDependencies(
        allocator,
        arena,
        root_prog_node,
    );
    defer {
        var iter = map.iterator();
        while (iter.next()) |dep| dep.value_ptr.deinit(allocator);
        map.deinit();
    }

    try map.put(0, root);

    const format: Format = if (args.mermaid != 0) blk: {
        break :blk .mermaid;
    } else blk: {
        break :blk .mermaid;
    };

    switch (format) {
        .mermaid => {
            try writer.writeAll("%%{init: {\"flowchart\": {\"htmlLabels\": false}} }%%\n");
            try writer.writeAll("graph TD;\n");

            var iter = map.iterator();
            while (iter.next()) |dep| {
                //try writer.print("    {x}[\"`", .{dep.value_ptr.fingerprint});
                //try dep.value_ptr.printMermaid(writer);
                //try writer.writeAll("`\"]\n");
                try dep.value_ptr.printMermaid(writer);

                for (dep.value_ptr.children.items) |child| {
                    try writer.print("    0x{x} --> 0x{x}\n", .{ dep.value_ptr.fingerprint, child });
                }
            }
        },
    }
}
