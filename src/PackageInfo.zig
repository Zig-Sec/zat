const std = @import("std");
const Allocator = std.mem.Allocator;

pub const fetch = @import("PackageInfo/fetch.zig");

pub const PackageInfo = @This();

/// Maps form `<fingerprint>@<version>` to a package info.
pub const PackageInfoMap = std.hash_map.StringHashMap(PackageInfo);

name: []const u8,
hash: []const u8,
url: []const u8,
fingerprint: u64,
version: std.SemanticVersion,
/// Child references via ref-tuple
children: std.ArrayList([]const u8),
ref: []const u8,
sversion: []const u8,

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
}

pub fn makeDepTreeStr(
    fp_key: []const u8,
    map: *const PackageInfo.PackageInfoMap,
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
                    try chain.append(try std.fmt.allocPrint(
                        allocator,
                        "{s} {s}",
                        .{
                            item.name,
                            item.sversion,
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
