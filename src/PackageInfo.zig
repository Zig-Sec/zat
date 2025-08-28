const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Package = @import("PackageInfo/Package.zig");

const Components = @import("root.zig").InspectBuild.injected.zat.Components;

pub const PackageInfo = @This();

/// Maps form `<fingerprint>@<version>` to a package info.
pub const Map = std.hash_map.StringHashMap(PackageInfo);

name: []const u8,
hash: []const u8,
url: []const u8,
fingerprint: u64,
version: std.SemanticVersion,
sversion: []const u8,
ref: []const u8,
/// Child references via ref-tuple.
children: std.ArrayListUnmanaged([]const u8),
/// The detected components of a package.
/// Components can be executables, packages, libraries, resources, etc.
components: ?Components = null,

/// Determine if `ref` is a child of the given package.
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

pub fn print(self: *const @This(), writer: *std.Io.Writer) !void {
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

pub fn printMermaid(self: *const @This(), writer: *std.Io.Writer) !void {
    try writer.print(
        "{x}[\"`<a href='{s}'>{s}</a>\n{s}`\"]\n",
        .{
            &self.sha256HashFromRef(),
            self.url,
            self.name,
            self.sversion,
        },
    );
}

pub fn sha256HashFromRef(self: *const @This()) [std.crypto.hash.sha2.Sha256.digest_length]u8 {
    return hashFromRef(self.ref);
}

pub fn hashFromRef(r: []const u8) [std.crypto.hash.sha2.Sha256.digest_length]u8 {
    var ref: [std.crypto.hash.sha2.Sha256.digest_length]u8 = .{0} ** std.crypto.hash.sha2.Sha256.digest_length;
    std.crypto.hash.sha2.Sha256.hash(r, &ref, .{});
    return ref;
}

pub fn deinit(self: *@This(), allocator: Allocator) void {
    allocator.free(self.name);
    allocator.free(self.hash);
    allocator.free(self.url);
    for (self.children.items) |child| allocator.free(child);
    self.children.deinit(allocator);
    allocator.free(self.ref);
    allocator.free(self.sversion);
    if (self.components) |comps| comps.deinit(allocator);
}

pub fn makeDepTreeStr(
    fp_key: []const u8,
    map: *const PackageInfo.Map,
    allocator: Allocator,
) ![]const u8 {
    var visited: std.ArrayListUnmanaged([]const u8) = .{};
    defer {
        for (visited.items) |item| allocator.free(item);
        visited.deinit(allocator);
    }

    var chain: std.ArrayListUnmanaged([]const u8) = .{};
    defer {
        for (chain.items) |item| allocator.free(item);
        chain.deinit(allocator);
    }

    var node = map.get(fp_key).?;

    // this is the leaf
    try chain.append(allocator, try std.fmt.allocPrint(
        allocator,
        "{s} {s}",
        .{
            node.name,
            node.sversion,
        },
    ));
    try visited.append(allocator, try allocator.dupe(u8, node.ref));

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
                    // TODO

                    try chain.append(allocator, try std.fmt.allocPrint(
                        allocator,
                        "{s} {s}",
                        .{
                            item.name,
                            item.sversion,
                        },
                    ));
                    try visited.append(allocator, try allocator.dupe(u8, item.ref));

                    node = map.get(item.ref).?;
                    continue :loop;
                }
            }
        }

        break;
    }

    var result = std.Io.Writer.Allocating.init(allocator);
    errdefer result.deinit();
    var offset: usize = 0;
    while (true) {
        const n = chain.pop();
        if (n == null) break;

        for (0..offset) |_| try result.writer.writeByte(' ');
        if (offset > 0) try result.writer.writeAll("└──");
        try result.writer.print("{s}\n", .{n.?});

        offset += 2;
    }

    return try result.toOwnedSlice();
}
