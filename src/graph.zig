const std = @import("std");
const Allocator = std.mem.Allocator;

const PackageInfo = @import("PackageInfo.zig");
const DepMap = PackageInfo.PackageInfoMap;

const audit = @import("audit.zig");

const Format = enum {
    mermaid,
};

pub fn cmdGraph(
    allocator: Allocator,
    arena: Allocator,
    args: anytype,
) !void {
    var map = try audit.fetchPackageDependencies(allocator, arena);
    defer {
        var iter = map.iterator();
        while (iter.next()) |dep| dep.value_ptr.deinit(allocator);
        map.deinit();
    }

    const format: Format = if (args.mermaid != 0) blk: {
        break :blk .mermaid;
    } else blk: {
        break :blk .mermaid;
    };

    var writer = std.io.getStdOut().writer();

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
