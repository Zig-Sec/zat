const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const BuildZigZon = struct {
    name: []const u8,
    version: std.SemanticVersion,
    fingerprint: u64,
    dependencies: std.ArrayList(Dependency),

    pub fn deinit(self: *const @This(), allocator: Allocator) void {
        allocator.free(self.name);
        for (self.dependencies.items) |item| item.deinit(allocator);
        self.dependencies.deinit();
    }

    pub const Dependency = struct {
        name: ?[]const u8 = null,
        url: ?[]const u8 = null,
        hash: ?[]const u8 = null,
        path: ?[]const u8 = null,
        lazy: bool = false,

        pub fn deinit(self: *const @This(), allocator: Allocator) void {
            if (self.name) |v| allocator.free(v);
            if (self.url) |v| allocator.free(v);
            if (self.hash) |v| allocator.free(v);
            if (self.path) |v| allocator.free(v);
        }
    };
};

pub fn parseBuildZigZon(allocator: Allocator, slice: [:0]const u8) !BuildZigZon {
    var ast = try std.zig.Ast.parse(allocator, slice, .zon);
    defer ast.deinit(allocator);

    var zoir = try std.zig.ZonGen.generate(
        allocator,
        ast,
        .{ .parse_str_lits = true },
    );
    defer zoir.deinit(allocator);

    const root = std.zig.Zoir.Node.Index.root.get(zoir);
    const root_struct = if (root == .struct_literal) root.struct_literal else return error.InvalidBuildZigZon;

    var name: ?[]const u8 = null;
    errdefer if (name) |v| allocator.free(v);
    var version: ?std.SemanticVersion = null;
    var dependencies = std.ArrayList(BuildZigZon.Dependency).init(allocator);
    errdefer {
        for (dependencies.items) |item| item.deinit(allocator);
        dependencies.deinit();
    }

    for (root_struct.names, 0..root_struct.vals.len) |name_node, index| {
        const value = root_struct.vals.at(@intCast(index));
        const name_ = name_node.get(zoir);

        if (std.mem.eql(u8, name_, "name")) {
            const ename = value.get(zoir).enum_literal;
            name = try allocator.dupe(u8, ename.get(zoir));
        } else if (std.mem.eql(u8, name_, "version")) {
            const v = value.get(zoir).string_literal;
            version = std.SemanticVersion.parse(v) catch {
                std.log.err(
                    "`{s}` version must adhere to semantic versioning",
                    .{v},
                );
                return error.InvalidVersionFormat;
            };
        } else if (std.mem.eql(u8, name_, "fingerprint")) {
            const f = value.get(zoir).int_literal;
            _ = f;
        } else if (std.mem.eql(u8, name_, "dependencies")) blk: {
            switch (value.get(zoir)) {
                .struct_literal => |lit| {
                    for (lit.names, 0..lit.vals.len) |depName, depIndex| {
                        const node = lit.vals.at(@intCast(depIndex));
                        var depBody = try std.zon.parse.fromZoirNode(
                            BuildZigZon.Dependency,
                            allocator,
                            ast,
                            zoir,
                            node,
                            null,
                            .{ .ignore_unknown_fields = true },
                        );
                        depBody.name = try allocator.dupe(u8, depName.get(zoir));

                        try dependencies.append(depBody);
                    }
                },
                .empty_literal => break :blk,
                else => return error.InvalidDependencyBlock,
            }
        }
    }

    if (name == null) return error.NameMissing;
    if (version == null) return error.VersionMissing;

    return .{
        .name = name.?,
        .version = version.?,
        .fingerprint = 0,
        .dependencies = dependencies,
    };
}

test "parse build.zig.zon #1" {
    const bzz: [:0]const u8 =
        \\.{
        \\  .name = .zrt,
        \\  .version = "0.1.0",
        \\  .fingerprint = 0xec469ac53ee70843, // Changing this has security and trust implications.
        \\  .minimum_zig_version = "0.14.0",
        \\  .dependencies = .{
        \\    .keylib = .{
        \\      .url = "https://github.com/r4gus/keylib/archive/refs/tags/0.6.0.tar.gz",
        \\      .hash = "1220017b7790baa2e2cb035fb925f56b21416d8de8d7e1b72379bc38d06c4eb3c8bf",
        \\    }
        \\  },
        \\  .paths = .{
        \\    "build.zig",
        \\    "build.zig.zon",
        \\    "src",
        \\    "README.md",
        \\  },
        \\}
    ;

    const b = try parseBuildZigZon(testing.allocator, bzz);
    defer b.deinit(testing.allocator);

    try std.testing.expectEqualSlices(u8, "zrt", b.name);
    try std.testing.expectEqual(std.SemanticVersion{
        .major = 0,
        .minor = 1,
        .patch = 0,
    }, b.version);

    try std.testing.expectEqualSlices(u8, "keylib", b.dependencies.items[0].name.?);
    try std.testing.expectEqualSlices(u8, "1220017b7790baa2e2cb035fb925f56b21416d8de8d7e1b72379bc38d06c4eb3c8bf", b.dependencies.items[0].hash.?);
    try std.testing.expectEqualSlices(u8, "https://github.com/r4gus/keylib/archive/refs/tags/0.6.0.tar.gz", b.dependencies.items[0].url.?);
}
