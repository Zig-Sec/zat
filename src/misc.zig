const std = @import("std");
const Allocator = std.mem.Allocator;
const Cache = std.Build.Cache;
const fs = std.fs;
const process = std.process;
const fatal = process.fatal;
const Color = std.zig.Color;
const Ast = std.zig.Ast;
const Package = @import("Package.zig");

pub const BuildRoot = struct {
    directory: Cache.Directory,
    build_zig_basename: []const u8,
    cleanup_build_dir: ?fs.Dir,

    pub fn deinit(br: *BuildRoot) void {
        if (br.cleanup_build_dir) |*dir| dir.close();
        br.* = undefined;
    }
};

pub const FindBuildRootOptions = struct {
    build_file: ?[]const u8 = null,
    cwd_path: ?[]const u8 = null,
};

pub fn findBuildRoot(arena: Allocator, options: FindBuildRootOptions) !BuildRoot {
    const cwd_path = options.cwd_path orelse try process.getCwdAlloc(arena);
    defer arena.free(cwd_path);

    const build_zig_basename = if (options.build_file) |bf|
        fs.path.basename(bf)
    else
        Package.build_zig_basename;

    if (options.build_file) |bf| {
        if (fs.path.dirname(bf)) |dirname| {
            const dir = fs.cwd().openDir(dirname, .{}) catch |err| {
                fatal("unable to open directory to build file from argument 'build-file', '{s}': {s}", .{ dirname, @errorName(err) });
            };
            return .{
                .build_zig_basename = build_zig_basename,
                .directory = .{ .path = dirname, .handle = dir },
                .cleanup_build_dir = dir,
            };
        }

        return .{
            .build_zig_basename = build_zig_basename,
            .directory = .{ .path = null, .handle = fs.cwd() },
            .cleanup_build_dir = null,
        };
    }
    // Search up parent directories until we find build.zig.
    var dirname: []const u8 = cwd_path;
    while (true) {
        const joined_path = try fs.path.join(arena, &[_][]const u8{ dirname, build_zig_basename });
        defer arena.free(joined_path);

        if (fs.cwd().access(joined_path, .{})) |_| {
            const dir = fs.cwd().openDir(dirname, .{}) catch |err| {
                fatal("unable to open directory while searching for build.zig file, '{s}': {s}", .{ dirname, @errorName(err) });
            };
            return .{
                .build_zig_basename = build_zig_basename,
                .directory = .{
                    .path = dirname,
                    .handle = dir,
                },
                .cleanup_build_dir = dir,
            };
        } else |err| switch (err) {
            error.FileNotFound => {
                dirname = fs.path.dirname(dirname) orelse {
                    std.log.info("initialize {s} template file with 'zig init'", .{
                        Package.build_zig_basename,
                    });
                    std.log.info("see 'zig --help' for more options", .{});
                    fatal("no build.zig file found, in the current directory or any parent directories", .{});
                };
                continue;
            },
            else => |e| return e,
        }
    }
}

pub const LoadManifestOptions = struct {
    root_name: []const u8,
    dir: fs.Dir,
    color: Color,
};

pub fn loadManifest(
    gpa: Allocator,
    arena: Allocator,
    options: LoadManifestOptions,
) !struct { Package.Manifest, Ast } {
    const manifest_bytes = while (true) {
        break options.dir.readFileAllocOptions(
            arena,
            Package.Manifest.basename,
            Package.Manifest.max_bytes,
            null,
            1,
            0,
        ) catch |err| {
            fatal("unable to load {s}: {s}", .{
                Package.Manifest.basename, @errorName(err),
            });
        };
    };
    var ast = try Ast.parse(gpa, manifest_bytes, .zon);
    errdefer ast.deinit(gpa);

    if (ast.errors.len > 0) {
        try std.zig.printAstErrorsToStderr(gpa, ast, Package.Manifest.basename, options.color);
        process.exit(2);
    }

    var manifest = try Package.Manifest.parse(gpa, ast, .{});
    errdefer manifest.deinit(gpa);

    if (manifest.errors.len > 0) {
        var wip_errors: std.zig.ErrorBundle.Wip = undefined;
        try wip_errors.init(gpa);
        defer wip_errors.deinit();

        const src_path = try wip_errors.addString(Package.Manifest.basename);
        try manifest.copyErrorsIntoBundle(ast, src_path, &wip_errors);

        var error_bundle = try wip_errors.toOwnedBundle("");
        defer error_bundle.deinit(gpa);
        error_bundle.renderToStdErr(options.color.renderOptions());

        process.exit(2);
    }
    return .{ manifest, ast };
}

pub fn sanitizeExampleName(arena: Allocator, bytes: []const u8) error{OutOfMemory}![]const u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    for (bytes, 0..) |byte, i| switch (byte) {
        '0'...'9' => {
            if (i == 0) try result.append(arena, '_');
            try result.append(arena, byte);
        },
        '_', 'a'...'z', 'A'...'Z' => try result.append(arena, byte),
        '-', '.', ' ' => try result.append(arena, '_'),
        else => continue,
    };
    if (!std.zig.isValidId(result.items)) return "foo";
    if (result.items.len > Package.Manifest.max_name_len)
        result.shrinkRetainingCapacity(Package.Manifest.max_name_len);

    return result.toOwnedSlice(arena);
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

pub fn createFile(path: []const u8, options: std.fs.File.CreateFlags) !std.fs.File {
    return if (path[0] == '~' and path[1] == '/') blk: {
        const home = std.c.getenv("HOME");
        if (home == null) return error.NoHome;
        var home_dir = try std.fs.openDirAbsolute(home.?[0..std.zig.c_builtins.__builtin_strlen(home.?)], .{});
        defer home_dir.close();
        const file = try home_dir.createFile(path[2..], options);
        break :blk file;
    } else if (path[0] == '/') blk: {
        const file = try std.fs.createFileAbsolute(path[0..], options);
        break :blk file;
    } else blk: {
        const file = try std.fs.cwd().createFile(path[0..], options);
        break :blk file;
    };
}
