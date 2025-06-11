const std = @import("std");
const Allocator = std.mem.Allocator;

const Advisory = @import("advisory").Advisory;

pub const fetch = @import("PackageInfo/fetch.zig");
pub const graph = @import("PackageInfo/src_graph.zig");

pub const Components = @import("cmd/inspect_build/injected.zig").zat.Components;

pub const PackageInfo = @This();

/// Maps form `<fingerprint>@<version>` to a package info.
pub const PackageInfoMap = std.hash_map.StringHashMap(PackageInfo);

name: []const u8,
hash: []const u8,
url: []const u8,
fingerprint: u64,
version: std.SemanticVersion,
/// Child references via ref-tuple.
children: std.ArrayList([]const u8),
ref: []const u8,
sversion: []const u8,
/// The detected components of a package.
components: ?Components = null,
/// The modules actually used by a component.
/// NOTE: `components` and `used_modules` MUST have the same number of elements,
/// with matching indices for corresponding component-module-relationships.
used_modules: std.ArrayList(UsedModules),

pub const UsedModules = struct {
    name: []const u8,
    /// Modules detected via a static analysis of the AST of the given package.
    modules: ?graph.Modules = null,

    pub const AffectedFunctionResult = struct {
        file_name: []const u8,
        function: []const u8,
    };

    pub fn deinit(self: *const @This(), allocator: Allocator) void {
        allocator.free(self.name);
        if (self.modules) |mods| mods.deinit();
    }

    pub fn affectedFunctionUsed(
        self: *const @This(),
        module_name: []const u8,
        functions: []const []const u8,
    ) ?AffectedFunctionResult {
        if (self.modules) |modules| {
            for (modules.mods.items) |mod| {
                if (std.mem.eql(u8, module_name, mod.name)) {
                    for (mod.containers.items) |cont| {
                        for (functions) |function| {
                            // TODO: this is a very naive approach. Two things to improve:
                            // - the static analysis when searching for module usages
                            // - the comparison
                            var i: usize = 0;
                            while (i + 1 < function.len and function[i] != '.') i += 1;
                            // We strip the module name from the access path as the user
                            // might have bound the module to a variable with a different
                            // name.
                            const f_stripped = function[i..];

                            for (cont.accesses.items) |access| {
                                std.debug.print("comparing '{s}' and '{s}'\n", .{ access, f_stripped });
                                if (std.mem.endsWith(u8, access, f_stripped)) {
                                    // TODO: there might be multiple usages but we only
                                    // report the first one found. This has to be improved
                                    // in the future.
                                    return .{
                                        .file_name = cont.name,
                                        .function = function,
                                    };
                                }
                            }
                        }
                    }
                }
            }
        }

        return null;
    }
};

pub fn isChild(self: *const @This(), ref: []const u8) bool {
    for (self.children.items) |child| {
        if (std.mem.eql(u8, child, ref)) return true;
    }
    return false;
}

/// A reference is a tuple `(name, fingerprint, version)` represented as string in the format `<name>:<fingerprint>@<version>`.
pub fn allocReference(name: []const u8, fingerprint: u64, v: []const u8, allocator: Allocator) ![]const u8 {
    return try std.fmt.allocPrint(
        allocator,
        "{s}:{x}@{s}",
        .{
            name,
            fingerprint,
            v,
        },
    );
}

pub fn allocVersion(version: std.SemanticVersion, allocator: Allocator) ![]const u8 {
    return try std.fmt.allocPrint(
        allocator,
        "{d}.{d}.{d}{s}{s}{s}{s}",
        .{
            version.major,
            version.minor,
            version.patch,
            if (version.pre) |_| "-" else "",
            if (version.pre) |pre| pre else "",
            if (version.build) |_| "+" else "",
            if (version.build) |build| build else "",
        },
    );
}

pub fn print(self: *const @This(), writer: anytype) !void {
    try writer.print(
        "{s}:\n  hash: {s}\n  url: {s}\n  fingerprint: {x}\n  version: {d}.{d}.{d}{s}{s}{s}{s}\n  dependencies:\n",
        .{
            self.name,
            self.hash,
            self.url,
            self.fingerprint,
            self.version.major,
            self.version.minor,
            self.version.patch,
            if (self.version.pre) |_| "-" else "",
            if (self.version.pre) |pre| pre else "",
            if (self.version.build) |_| "+" else "",
            if (self.version.build) |build| build else "",
        },
    );
    for (self.children.items) |child| {
        try writer.print("    {x}\n", .{child});
    }
}

pub fn sha256HashFromRef(self: *const @This()) [std.crypto.hash.sha2.Sha256.digest_length]u8 {
    return hashFromRef(self.ref);
}

pub fn hashFromRef(r: []const u8) [std.crypto.hash.sha2.Sha256.digest_length]u8 {
    var ref: [std.crypto.hash.sha2.Sha256.digest_length]u8 = .{0} ** std.crypto.hash.sha2.Sha256.digest_length;
    std.crypto.hash.sha2.Sha256.hash(r, &ref, .{});
    return ref;
}

pub fn printMermaid(self: *const @This(), writer: anytype) !void {
    try writer.print(
        "{x}[\"`<a href='{s}'>{s}</a>\n{s}`\"]\n",
        .{
            std.fmt.fmtSliceHexLower(&self.sha256HashFromRef()),
            self.url,
            self.name,
            self.sversion,
        },
    );
}

pub fn deinit(self: *const @This(), allocator: Allocator) void {
    allocator.free(self.name);
    allocator.free(self.hash);
    allocator.free(self.url);
    for (self.children.items) |child| allocator.free(child);
    self.children.deinit();
    allocator.free(self.ref);
    allocator.free(self.sversion);
    if (self.components) |comps| comps.deinit(allocator);
    for (self.used_modules.items) |comp| comp.deinit(allocator);
    self.used_modules.deinit();
}

pub fn makeDepTreeStr(
    fp_key: []const u8,
    map: *const PackageInfo.PackageInfoMap,
    advisory: *const Advisory,
    allocator: Allocator,
) ![]const u8 {
    var visited = std.ArrayList([]const u8).init(allocator);
    defer {
        for (visited.items) |item| allocator.free(item);
        visited.deinit();
    }

    var chain = std.ArrayList([]const u8).init(allocator);
    defer {
        for (chain.items) |item| allocator.free(item);
        chain.deinit();
    }

    var node = map.get(fp_key).?;

    // this is the leaf
    try chain.append(try std.fmt.allocPrint(
        allocator,
        "{s} {s}",
        .{
            node.name,
            node.sversion,
        },
    ));
    try visited.append(try allocator.dupe(u8, node.ref));

    loop: while (true) {
        var ci = map.valueIterator();
        while (ci.next()) |item| {
            var seen = false;
            for (visited.items) |n| {
                if (std.mem.eql(u8, n, item.ref)) {
                    seen = true;
                    break;
                }
            }

            for (item.children.items) |child| {
                if (std.mem.eql(u8, child, node.ref) and seen) {
                    break :loop; //TODO is this enough to catch infinite loops?
                } else if (std.mem.eql(u8, child, node.ref)) {
                    // Check if the parent has used one of the vulnerable functions
                    // if present.
                    var used_str: ?[]const u8 = null;
                    defer if (used_str) |str| allocator.free(str);
                    if (std.mem.eql(u8, child, fp_key)) outer: {
                        //std.debug.print("direct child\n", .{});
                        if (advisory.affected) |affected| {
                            //std.debug.print("affected\n", .{});
                            if (affected.functions) |functions| {
                                //std.debug.print("functions\n", .{});
                                for (item.used_modules.items) |comp| {
                                    //std.debug.print("{s}\n", .{comp.name});
                                    if (comp.affectedFunctionUsed(advisory.package, functions)) |used| {
                                        used_str = try std.fmt.allocPrint(
                                            allocator,
                                            "[warning: function '{s}' used in '{s}']",
                                            .{
                                                used.function,
                                                used.file_name,
                                            },
                                        );
                                        break :outer;
                                    }
                                }
                            }
                        }
                    }

                    try chain.append(try std.fmt.allocPrint(
                        allocator,
                        "{s} {s} {s}",
                        .{
                            item.name,
                            item.sversion,
                            if (used_str) |str| str else "",
                        },
                    ));
                    try visited.append(try allocator.dupe(u8, item.ref));

                    node = map.get(item.ref).?;
                    continue :loop;
                }
            }
        }

        break;
    }

    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();
    var offset: usize = 0;
    while (true) {
        const n = chain.pop();
        if (n == null) break;

        for (0..offset) |_| try result.append(' ');
        if (offset > 0) try result.appendSlice("└──");
        try result.writer().print("{s}\n", .{n.?});

        offset += 2;
    }

    return try result.toOwnedSlice();
}

test {
    _ = fetch;
}
