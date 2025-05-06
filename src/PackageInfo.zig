const std = @import("std");
const Allocator = std.mem.Allocator;

pub const PackageInfo = @This();

/// Maps form `<fingerprint>@<version>` to a package info.
pub const PackageInfoMap = std.hash_map.StringHashMap(PackageInfo);

name: []const u8,
hash: []const u8,
url: []const u8,
fingerprint: u64,
version: std.SemanticVersion,
/// Child references via fingerprints
children: std.ArrayList([]const u8),

/// A reference is a tuple `(fingerprint, version)` represented as string in the format `<fingerprint>@<version>`.
pub fn allocReference(self: *const @This(), allocator: Allocator) ![]const u8 {
    return try std.fmt.allocPrint(
        allocator,
        "{x}@{d}.{d}.{d}{s}{s}{s}{s}",
        .{
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

pub fn printMermaid(self: *const @This(), writer: anytype) !void {
    try writer.print(
        "{x}[\"`<a href='{s}'>{s}</a>\nv{d}.{d}.{d}{s}{s}{s}{s}`\"]\n",
        .{
            self.fingerprint,
            self.url,
            self.name,
            self.version.major,
            self.version.minor,
            self.version.patch,
            if (self.version.pre) |_| "-" else "",
            if (self.version.pre) |pre| pre else "",
            if (self.version.build) |_| "+" else "",
            if (self.version.build) |build| build else "",
        },
    );
}

pub fn deinit(self: *const @This(), allocator: Allocator) void {
    allocator.free(self.name);
    allocator.free(self.hash);
    allocator.free(self.url);
    for (self.children.items) |child| allocator.free(child);
    self.children.deinit();
}
