// https://github.com/ziglang/zig/blob/9bbac4288697f056f0cdb0c6ac597e9b1b18ea12/src/main.zig#L7066

const std = @import("std");
const Allocator = std.mem.Allocator;
const Cache = std.Build.Cache;
const fs = std.fs;
const process = std.process;
const fatal = process.fatal;
const Color = std.zig.Color;
const Ast = std.zig.Ast;

const Package = @import("Package.zig");

const misc = @import("misc.zig");

const stdout = std.io.getStdOut();
const stdin = std.io.getStdIn();

pub fn cmdNewRelease(
    allocator: Allocator,
    arena: Allocator,
    args: anytype,
) !void {
    const color: Color = .auto;

    const cwd_path = try std.process.getCwdAlloc(allocator);
    defer allocator.free(cwd_path);

    var build_root = try misc.findBuildRoot(arena, .{
        .cwd_path = cwd_path,
    });
    defer build_root.deinit();

    const init_root_name = fs.path.basename(build_root.directory.path orelse cwd_path);
    var manifest, var ast = try misc.loadManifest(allocator, arena, .{
        .root_name = try misc.sanitizeExampleName(arena, init_root_name),
        .dir = build_root.directory.handle,
        .color = color,
    });
    defer {
        manifest.deinit(allocator);
        ast.deinit(allocator);
    }

    var fixups: Ast.Fixups = .{};
    defer fixups.deinit(allocator);

    // Bump up version number. The default is patch.
    var version = manifest.version;
    if (args.major != 0) {
        version.major += 1;
        version.minor = 0;
        version.patch = 0;
    } else if (args.minor != 0) {
        version.minor += 1;
        version.patch = 0;
    } else {
        version.patch += 1;
    }
    const version_replace = try std.fmt.allocPrint(
        arena,
        "\"{d}.{d}.{d}\"",
        .{ version.major, version.minor, version.patch },
    );
    try fixups.replace_nodes_with_string.put(allocator, manifest.version_node, version_replace);

    try stdout.writeAll("The following changes have been made:\n");
    try stdout.writer().print("  version: {d}.{d}.{d}\n", .{
        version.major,
        version.minor,
        version.patch,
    });

    var accept: bool = false;
    if (args.y == 0) {
        var buffer: [2]u8 = .{0} ** 2;
        try stdout.writeAll("accept? [y\\n]: ");
        _ = try stdin.read(&buffer);

        if (buffer[0] == 'y') accept = true;
    } else {
        accept = true;
    }

    if (accept) {
        var rendered = std.ArrayList(u8).init(allocator);
        defer rendered.deinit();
        try ast.renderToArrayList(&rendered, fixups);

        build_root.directory.handle.writeFile(.{ .sub_path = Package.Manifest.basename, .data = rendered.items }) catch |err| {
            fatal("unable to write {s} file: {s}", .{ Package.Manifest.basename, @errorName(err) });
        };
    }
}
