const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;
const process = std.process;
const fatal = process.fatal;
const Color = std.zig.Color;
const Ast = std.zig.Ast;
const ThreadPool = std.Thread.Pool;
const Directory = std.Build.Cache.Directory;

const PackageInfo = @import("../PackageInfo.zig");
const DepMap = PackageInfo.PackageInfoMap;

const misc = @import("../misc.zig");

const git = @import("../git.zig");

const builtin = @import("builtin");

const Package = @import("../Package.zig");

const src_graph = @import("src_graph.zig");

const BuildScript = @import("../BuildScript.zig");

const cmd = @import("../cmd.zig");

pub fn fetchPackageDependencies(
    allocator: Allocator,
    arena: Allocator,
    node: std.Progress.Node,
) !struct { PackageInfo, DepMap } {
    const color: Color = .auto;

    var fetch_node = node.start("Fetch Dependencies", 0);
    defer fetch_node.end();

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

    var dep_map = DepMap.init(arena);
    errdefer {
        var iter = dep_map.iterator();
        while (iter.next()) |dep| dep.value_ptr.deinit(allocator);
        dep_map.deinit();
    }

    var dependencies = std.ArrayList([]const u8).init(allocator);
    defer dependencies.deinit();

    var deps_iter = manifest.dependencies.iterator();
    while (deps_iter.next()) |dep| {
        try dependencies.append(dep.value_ptr.location.url);
    }

    // +++++++++++++++++++++++++++++++++++++++
    // Infos about the package
    // +++++++++++++++++++++++++++++++++++++++
    const fp = genFingerprint(manifest.name, manifest.id);
    const v = try PackageInfo.allocVersion(manifest.version, allocator);
    errdefer allocator.free(v);
    const ref = try PackageInfo.allocReference(manifest.name, fp, v, allocator);
    errdefer allocator.free(ref);

    // TODO: provide all information
    var root_package = PackageInfo{
        .name = try allocator.dupe(u8, manifest.name),
        .hash = try allocator.dupe(u8, ""),
        .url = try allocator.dupe(u8, ""),
        .fingerprint = fp,
        .version = manifest.version,
        .children = std.ArrayList([]const u8).init(allocator),
        .ref = ref,
        .sversion = v,
        .used_modules = std.ArrayList(PackageInfo.UsedModules).init(allocator),
    };
    errdefer root_package.deinit(allocator);

    // Try to get more information...
    {
        // Parse the Git config (if it exists)
        // TODO: the package uri might get added to `build.zig.zon` together with the version: https://github.com/ziglang/zig/issues/23816
        const git_config = git.GitConfig.load(allocator) catch |e| blk: {
            std.log.warn("unable to load Git config ({any})", .{e});
            break :blk null;
        };
        if (git_config) |conf| {
            if (conf.remote_origin.url) |url| {
                root_package.url = try allocator.dupe(u8, url);
            }

            conf.deinit();
        }
    }

    // Try to inspect the build graph to get more detailed infromation
    // about the given package.
    var inspect_build_node = fetch_node.start("inspecting build", 0);
    outer: {
        root_package.components = cmd.inspect_build.inspect(build_root.directory.handle, allocator) catch break :outer;
    }
    inspect_build_node.end();

    // TODO: test code for parsing the source files
    var inspect_rsf_node = fetch_node.start("analyzing root source files", 0);
    if (root_package.components) |comps| {
        for (comps.components) |comp| {
            if (comp.root_source_file) |rsf| {
                const mods = src_graph.getUsedModules(allocator, build_root.directory.handle, rsf) catch |e| {
                    std.log.warn("failed to check modules for '{s}' ({any})", .{ rsf, e });
                    continue;
                };
                errdefer mods.deinit();

                try root_package.used_modules.append(.{
                    .name = try allocator.dupe(u8, comp.name),
                    .modules = mods,
                });
            }
        }
    }
    inspect_rsf_node.end();

    // +++++++++++++++++++++++++++++++++++++++
    // Infos about its dependencies
    // +++++++++++++++++++++++++++++++++++++++

    try fetchDependencies(
        allocator,
        arena,
        dependencies.items,
        fetch_node,
        &dep_map,
        &root_package,
    );

    return .{ root_package, dep_map };
}

pub fn fetchDependencies(
    allocator: Allocator,
    arena: Allocator,
    dep_paths: []const []const u8,
    node: std.Progress.Node,
    map: *DepMap,
    parent: ?*PackageInfo,
) !void {
    for (dep_paths) |dep| {
        //std.debug.print("{s}\n", .{dep});

        const dep_, const children = fetchDependency(
            allocator,
            arena,
            dep,
            node,
            parent,
        ) catch {
            std.log.warn("{s} is missing a manifest", .{dep});
            continue;
        };

        defer {
            for (children) |child| allocator.free(child);
            allocator.free(children);
        }

        if (!map.contains(dep_.ref)) {
            try map.put(try allocator.dupe(u8, dep_.ref), dep_);

            try fetchDependencies(
                allocator,
                arena,
                children,
                node,
                map,
                map.getPtr(dep_.ref).?,
            );
        }
    }
}

pub fn fetchDependency(
    allocator: Allocator,
    arena: Allocator,
    path_or_url: []const u8,
    node: std.Progress.Node,
    parent: ?*PackageInfo,
) !struct { PackageInfo, []const []const u8 } {
    _ = arena;

    var node2 = node.start(path_or_url, 0);
    defer node2.end();

    const color: Color = .auto;
    const override_global_cache_dir: ?[]const u8 = try std.zig.EnvVar.ZIG_GLOBAL_CACHE_DIR.get(allocator);
    defer if (override_global_cache_dir) |over| allocator.free(over);
    const work_around_btrfs_bug = builtin.os.tag == .linux and
        std.zig.EnvVar.ZIG_BTRFS_WORKAROUND.isSet();

    var thread_pool: ThreadPool = undefined;
    try thread_pool.init(.{ .allocator = allocator });
    defer thread_pool.deinit();

    var http_client: std.http.Client = .{ .allocator = allocator };
    defer http_client.deinit();

    try http_client.initDefaultProxies(allocator);
    //defer {
    //    http_client.connection_pool.deinit(allocator);
    //    http_client.deinit();
    //}

    var global_cache_directory: Directory = l: {
        const p = override_global_cache_dir orelse try resolveGlobalCacheDir(allocator);
        break :l .{
            .handle = try fs.cwd().makeOpenPath(p, .{}),
            .path = p,
        };
    };
    defer global_cache_directory.closeAndFree(allocator);

    var job_queue: Package.Fetch.JobQueue = .{
        .http_client = &http_client,
        .thread_pool = &thread_pool,
        .global_cache = global_cache_directory,
        .recursive = false,
        .read_only = false,
        .debug_hash = false,
        .work_around_btrfs_bug = work_around_btrfs_bug,
    };
    defer job_queue.deinit();

    var fetch: Package.Fetch = .{
        .arena = std.heap.ArenaAllocator.init(allocator),
        .location = .{ .path_or_url = path_or_url },
        .location_tok = 0,
        .hash_tok = 0,
        .name_tok = 0,
        .lazy_status = .eager,
        .parent_package_root = undefined,
        .parent_manifest_ast = null,
        .prog_node = node,
        .job_queue = &job_queue,
        .omit_missing_hash_error = true,
        .allow_missing_paths_field = false,
        .allow_missing_fingerprint = true,
        .allow_name_string = true,
        .use_latest_commit = true,

        .package_root = undefined,
        .error_bundle = undefined,
        .manifest = null,
        .manifest_ast = undefined,
        .computed_hash = undefined,
        .has_build_zig = false,
        .oom_flag = false,
        .latest_commit = null,

        //.module = null,
    };
    defer fetch.deinit();

    fetch.run() catch |err| switch (err) {
        error.OutOfMemory => fatal("out of memory", .{}),
        error.FetchFailed => {}, // error bundle checked below
    };

    if (fetch.error_bundle.root_list.items.len > 0) {
        var errors = try fetch.error_bundle.toOwnedBundle("");
        errors.renderToStdErr(color.renderOptions());
        process.exit(1);
    }

    var child_deps = std.ArrayList([]const u8).init(allocator);
    errdefer child_deps.deinit();

    if (fetch.manifest) |manifest| {
        const fp = genFingerprint(manifest.name, manifest.id);
        const v = try PackageInfo.allocVersion(manifest.version, allocator);
        errdefer allocator.free(v);
        const ref = try PackageInfo.allocReference(manifest.name, fp, v, allocator);
        errdefer allocator.free(ref);

        var children_iter = manifest.dependencies.iterator();
        while (children_iter.next()) |child| {
            try child_deps.append(try allocator.dupe(u8, child.value_ptr.location.url));
        }

        var pi = PackageInfo{
            .name = try allocator.dupe(u8, manifest.name),
            .hash = try allocator.dupe(u8, fetch.computedPackageHash().toSlice()),
            .url = try allocator.dupe(u8, path_or_url),
            .fingerprint = fp,
            .version = manifest.version,
            .children = std.ArrayList([]const u8).init(allocator),
            .ref = ref,
            .sversion = v,
            .used_modules = std.ArrayList(PackageInfo.UsedModules).init(allocator),
        };

        var node3 = node2.start("static analysis", 0);
        // TODO: test code for parsing the source files
        outer: {
            const dir = fetch.package_root.root_dir.handle.openDir("src", .{}) catch break :outer;

            resolveUsedModules(allocator, dir, &.{ "root.zig", "main.zig" }, &pi) catch {
                break :outer;
            };
        }
        node3.end();

        // Connect the package to the parent
        if (parent) |p| try p.children.append(try allocator.dupe(u8, ref));

        return .{
            pi,
            try child_deps.toOwnedSlice(),
        };
    }

    return error.NoManifest;
}

/// Caller owns returned memory.
pub fn resolveGlobalCacheDir(allocator: Allocator) ![]u8 {
    if (builtin.os.tag == .wasi)
        @compileError("on WASI the global cache dir must be resolved with preopens");

    if (try std.zig.EnvVar.ZIG_GLOBAL_CACHE_DIR.get(allocator)) |value| return value;

    const appname = "zig";

    if (builtin.os.tag != .windows) {
        if (std.zig.EnvVar.XDG_CACHE_HOME.getPosix()) |cache_root| {
            if (cache_root.len > 0) {
                return fs.path.join(allocator, &[_][]const u8{ cache_root, appname });
            }
        }
        if (std.zig.EnvVar.HOME.getPosix()) |home| {
            return fs.path.join(allocator, &[_][]const u8{ home, ".cache", appname });
        }
    }

    return fs.getAppDataDir(allocator, appname);
}

pub fn genFingerprint(name: []const u8, id: u32) u64 {
    return @as(u64, @intCast(std.hash.Crc32.hash(name))) << 32 | id;
}

/// Statically analyze the AST beginning from a root source file and determine used
/// modules.
pub fn resolveUsedModules(
    allocator: Allocator,
    dir: std.fs.Dir,
    root_source_files: []const []const u8,
    pi: *PackageInfo,
) !void {
    for (root_source_files) |file_path| {
        const mods = src_graph.getUsedModules(allocator, dir, file_path) catch |e| {
            std.log.warn("failed to check modules for '{s}' ({any})", .{ file_path, e });
            continue;
        };
        errdefer mods.deinit();

        try pi.used_modules.append(.{
            .name = try allocator.dupe(u8, file_path),
            .modules = mods,
        });
    }
}
