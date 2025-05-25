const std = @import("std");
const Allocator = std.mem.Allocator;

const PackageInfo = @import("../PackageInfo.zig");

const ZigsecAdvisoryApi = @import("../ZigsecAdvisoryApi.zig");

const stdout = std.io.getStdOut();
const stdin = std.io.getStdIn();

pub fn cmdAudit(
    allocator: Allocator,
    arena: Allocator,
    args: anytype,
) !void {
    _ = args;

    var vulnerability_counter: usize = 0;

    // This client is used to access the advisory db on Github.
    var http_client: std.http.Client = .{ .allocator = allocator };
    defer http_client.deinit();
    try http_client.initDefaultProxies(allocator);

    var root_prog_node = std.Progress.start(.{
        .root_name = "Scanning build.zig.zon",
    });

    // Here we fetch the dependencies specified in build.zig.zon. This is the
    // same code as used by the standard libraries `zig build`.
    //
    // TODO: They should make this API public so I/we don't have to copy the code
    // but maybe it's better to simplify the process as we only need the build.zig.zon.
    // Maybe we need more later on...
    var root, var map = try PackageInfo.fetch.fetchPackageDependencies(
        allocator,
        arena,
        root_prog_node,
    );
    defer root.deinit(allocator);

    root_prog_node.end();

    try stdout.writer().print("Scanning build.zig.zon for vulnerabilities ({d} package dependencies)\n", .{map.count()});

    // We iterate over every (transitive) dependency and try to fetch advisories.
    var deps_iter2 = map.iterator();
    while (deps_iter2.next()) |dep| {
        // TODO: For now we only look for advisories @ Zig-Sec/advisory-db
        const advisories = ZigsecAdvisoryApi.fetchAdvisories(
            &http_client,
            dep.value_ptr.name,
            allocator,
        ) catch |e| {
            std.log.warn("no advisories for '{s}' ({any})", .{ dep.value_ptr.name, e });
            continue;
        };
        defer {
            for (advisories) |adv| adv.deinit(allocator);
            allocator.free(advisories);
        }

        // If the advisory is applicable, i.e. the dependency contains a vulnerability,
        // display information about it.
        //
        for (advisories) |adv| {
            if (adv.fingerprint == dep.value_ptr.fingerprint and adv.vulnerable(dep.value_ptr.version)) {
                const tree = try PackageInfo.makeDepTreeStr(dep.value_ptr.ref, &map, &adv, allocator);
                defer allocator.free(tree);

                try stdout.writer().print(
                    \\
                    \\Package:      {s}
                    \\Version:      {s}
                    \\Title:        {s}
                    \\Date:         {s}
                    \\ID:           {s}
                    \\URL:          https://zigsec.org/advisories/{s}/
                    \\Solution:     {s}
                    \\Dependency tree:
                    \\{s}
                    \\
                ,
                    .{
                        adv.package,
                        dep.value_ptr.sversion,
                        adv.description,
                        adv.date,
                        adv.id,
                        adv.id,
                        if (adv.recommended) |rec| rec else "None",
                        tree,
                    },
                );

                vulnerability_counter += 1;
            }
        }
    }

    if (vulnerability_counter > 0) {
        try stdout.writer().print("\nerror: {d} {s} found!\n", .{
            vulnerability_counter,
            if (vulnerability_counter > 1) "vulnerabilities" else "vulnerability",
        });
    }
}
