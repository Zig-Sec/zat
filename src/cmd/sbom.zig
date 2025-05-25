const std = @import("std");
const Allocator = std.mem.Allocator;
const fatal = std.process.fatal;

const PackageInfo = @import("../PackageInfo.zig");
const DepMap = PackageInfo.PackageInfoMap;

const misc = @import("../misc.zig");

const cyclonedx = @import("../cyclonedx.zig");

const time = @import("../time.zig");

const Format = enum {
    cdx_json,
};

pub fn cmdSbom(
    allocator: Allocator,
    arena: Allocator,
    args: anytype,
) !void {
    var f: ?std.fs.File = null;
    defer if (f) |f_| f_.close();

    var root_prog_node = std.Progress.start(.{
        .root_name = "generate SBOM",
    });

    const writer = if (args.path) |path| blk: {
        f = try misc.createFile(path, .{});
        break :blk f.?.writer();
    } else blk: {
        break :blk std.io.getStdOut().writer();
    };

    const root, var map = try PackageInfo.fetch.fetchPackageDependencies(
        allocator,
        arena,
        root_prog_node,
    );
    defer {
        var iter = map.iterator();
        while (iter.next()) |dep| dep.value_ptr.deinit(allocator);
        map.deinit();
    }

    var sbom = cyclonedx.SBOM.new(allocator) catch |err| {
        fatal("unable to create SBOM ({any})", .{err});
    };
    defer sbom.deinit(allocator);

    // meta
    {
        const zat_tool_comp = try cyclonedx.makeZatToolComponent(allocator);
        errdefer zat_tool_comp.deinit(allocator);

        const tools = try allocator.alloc(cyclonedx.Component, 1);
        errdefer allocator.free(tools);
        tools[0] = zat_tool_comp;

        const comp, const dep = try cyclonedx.componentFromPackageInfo(allocator, &root, &map, .application);
        errdefer {
            comp.deinit(allocator);
            dep.deinit(allocator);
        }

        const t = time.DateTime.now();

        sbom.metadata = .{
            .timestamp = try t.formatAlloc(allocator, "YYYY-MM-DDTHH:mm:ss"),
            .tools = .{
                .components = tools,
            },
            .component = comp,
        };
        try sbom.addDependency(dep, allocator);
    }

    {
        var components_iterator = map.valueIterator();
        while (components_iterator.next()) |info| {
            const comp, const dep = try cyclonedx.componentFromPackageInfo(allocator, info, &map, .library);
            errdefer {
                comp.deinit(allocator);
                dep.deinit(allocator);
            }

            try sbom.addComponent(comp, allocator);
            try sbom.addDependency(dep, allocator);
        }
    }

    root_prog_node.end(); // this comes right before writing...
    try std.json.stringify(
        sbom,
        .{
            .whitespace = .indent_2,
            .emit_null_optional_fields = false,
        },
        writer,
    );
    _ = try writer.write("\n");
}
