const std = @import("std");
const Allocator = std.mem.Allocator;
const Cache = std.Build.Cache;
const fs = std.fs;
const process = std.process;
const fatal = process.fatal;
const Color = std.zig.Color;
const Ast = std.zig.Ast;
const ThreadPool = std.Thread.Pool;
const Directory = std.Build.Cache.Directory;

const advisory = @import("advisory");
const Advisory = advisory.Advisory;

const PackageInfo = @import("PackageInfo.zig");
const DepMap = PackageInfo.PackageInfoMap;

const builtin = @import("builtin");

const Package = @import("Package.zig");

const misc = @import("misc.zig");

const stdout = std.io.getStdOut();
const stdin = std.io.getStdIn();

pub fn cmdAudit(
    allocator: Allocator,
    arena: Allocator,
    args: anytype,
) !void {
    _ = args;

    var vulnerability_counter: usize = 0;

    var root_prog_node = std.Progress.start(.{
        .root_name = "Scanning build.zig.zon",
    });

    var root, var map = try fetchPackageDependencies(
        allocator,
        arena,
        root_prog_node,
    );
    defer root.deinit(allocator);

    root_prog_node.end();

    try stdout.writer().print("Scanning build.zig.zon for vulnerabilities ({d} package dependencies)\n", .{map.count()});

    var deps_iter2 = map.iterator();
    while (deps_iter2.next()) |dep| {
        const advisories = fetchAdvisories(allocator, dep.value_ptr.fingerprint) catch |e| {
            std.log.err("error fetching advisories for '{s}' ({any})", .{ dep.value_ptr.name, e });
            continue;
        };
        defer {
            for (advisories) |adv| adv.deinit(allocator);
            allocator.free(advisories);
        }

        for (advisories) |adv| {
            if (adv.vulnerable(dep.value_ptr.version)) {
                try stdout.writer().print(
                    \\
                    \\Package:      {s}
                    \\Version:      {d}.{d}.{d}
                    \\Title:        {s}
                    \\Date:         {s}
                    \\ID:           {s}
                    \\URL:          https://zigsec.org/advisories/{s}/
                    \\Solution:     {s}
                    \\
                ,
                    .{
                        adv.package,
                        dep.value_ptr.version.major,
                        dep.value_ptr.version.minor,
                        dep.value_ptr.version.patch,
                        adv.description,
                        adv.date,
                        adv.id,
                        adv.id,
                        if (adv.recommended) |rec| rec else "None",
                    },
                );

                vulnerability_counter += 1;
            }
        }

        //try dep.value_ptr.print(stdout.writer());
    }

    if (vulnerability_counter > 0) {
        try stdout.writer().print("\nerror: {d} {s} found!\n", .{
            vulnerability_counter,
            if (vulnerability_counter > 1) "vulnerabilities" else "vulnerability",
        });
    }
}

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

    // TODO: provide all information
    var root_package = PackageInfo{
        .name = try allocator.dupe(u8, manifest.name),
        .hash = try allocator.dupe(u8, ""),
        .url = try allocator.dupe(u8, ""),
        .fingerprint = 0,
        .version = manifest.version,
        .children = std.ArrayList(u64).init(allocator),
    };
    errdefer root_package.deinit(allocator);

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
        const fp = dep_.fingerprint;

        if (!map.contains(fp)) {
            try map.put(fp, dep_);

            try fetchDependencies(
                allocator,
                arena,
                children,
                node,
                map,
                map.getPtr(fp).?,
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

    if (fetch.manifest) |manifest| {
        const fp = @as(u64, @intCast(std.hash.Crc32.hash(manifest.name))) << 32 | manifest.id;
        if (parent) |p| try p.children.append(fp);

        var children_iter = manifest.dependencies.iterator();
        while (children_iter.next()) |child| {
            try child_deps.append(try allocator.dupe(u8, child.value_ptr.location.url));
        }

        return .{
            .{
                .name = try allocator.dupe(u8, manifest.name),
                .hash = try allocator.dupe(u8, fetch.computedPackageHash().toSlice()),
                .url = try allocator.dupe(u8, path_or_url),
                .fingerprint = fp,
                .version = manifest.version,
                .children = std.ArrayList(u64).init(allocator),
            },
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

pub fn fetchAdvisories(
    allocator: Allocator,
    fingerprint: u64,
) ![]const Advisory {
    var advisories = std.ArrayList(Advisory).init(allocator);
    errdefer advisories.deinit();

    const fingerprint_string = try std.fmt.allocPrint(allocator, "{x}", .{fingerprint});
    defer allocator.free(fingerprint_string);

    var http_client: std.http.Client = .{ .allocator = allocator };
    defer http_client.deinit();

    try http_client.initDefaultProxies(allocator);

    var response_body = std.ArrayList(u8).init(allocator);
    defer response_body.deinit();

    const fingerprint_url = try std.fmt.allocPrint(allocator, "https://api.github.com/repos/Zig-Sec/advisory-db/contents/packages/{s}", .{fingerprint_string});
    defer allocator.free(fingerprint_url);

    const response = try http_client.fetch(.{
        .headers = .{
            .accept_encoding = .{ .override = "application/vnd.github+json" },
        },
        .method = .GET,
        .location = .{ .url = fingerprint_url },
        .response_storage = .{ .dynamic = &response_body },
    });
    _ = response;

    //std.debug.print("{s}\n", .{response_body.items});

    const files = std.json.parseFromSliceLeaky(
        GithubApi.FileResponse,
        allocator,
        response_body.items,
        .{
            .ignore_unknown_fields = true,
        },
    ) catch {
        // We are unable to parse the response, i.e., no advisories found.
        return try advisories.toOwnedSlice();
    };

    //for (files) |file| std.debug.print("{s}\n", .{file.name});

    for (files) |file| {
        var response_body2 = std.ArrayList(u8).init(allocator);
        defer response_body2.deinit();

        _ = try http_client.fetch(.{
            .headers = .{
                .accept_encoding = .{ .override = "application/vnd.github+json" },
            },
            .method = .GET,
            .location = .{ .url = file.url },
            .response_storage = .{ .dynamic = &response_body2 },
        });

        //std.debug.print("{s}\n", .{response_body2.items});

        const advisory_file = std.json.parseFromSliceLeaky(
            GithubApi.File,
            allocator,
            response_body2.items,
            .{
                .ignore_unknown_fields = true,
            },
        ) catch |e| {
            std.log.err("unable to parse '{s}' advisory file ({any})! Please consider reporting this as an issue.", .{ file.name, e });
            continue;
        };

        var b64 = std.ArrayList(u8).init(allocator);
        defer b64.deinit();
        var iter = std.mem.splitAny(u8, advisory_file.content, "\n");
        while (iter.next()) |chunk| try b64.appendSlice(chunk);

        //std.debug.print("{s}\n", .{b64.items});

        const l = std.base64.standard.Decoder.calcSizeForSlice(b64.items) catch |e| {
            std.log.err("unable to calc size for bas64 string ({any})\n", .{e});
            continue;
        };
        const dest = try allocator.alloc(u8, l);
        defer allocator.free(dest);

        std.base64.standard.Decoder.decode(dest, b64.items) catch |e| {
            std.log.err("unable to decode base64 ({any})\n", .{e});
            continue;
        };

        //std.debug.print("{s}\n", .{dest});
        const s = try allocator.dupeZ(u8, dest);
        defer allocator.free(s);

        const package_advisory = try std.zon.parse.fromSlice(
            Advisory,
            allocator,
            s,
            null,
            .{ .ignore_unknown_fields = true },
        );

        //std.debug.print("{any}\n", .{package_advisory});

        try advisories.append(package_advisory);
    }

    return try advisories.toOwnedSlice();
}

pub const GithubApi = struct {
    pub const FileResponse = []const FileDescriptor;

    pub const FileDescriptor = struct {
        name: []const u8,
        url: []const u8,

        pub fn deinit(self: *const @This(), allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.url);
        }
    };

    pub const File = struct {
        content: []const u8,
        encoding: []const u8,
        html_url: []const u8,

        pub fn deinit(self: *const @This(), allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.encoding);
            allocator.free(self.html_url);
        }
    };
};
