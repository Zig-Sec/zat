//! Defines the direct dependencies of a component, service, or the components provided/implemented by a given component. Components or services that do not have their own dependencies must be declared as empty elements within the graph. Components or services that are not represented in the dependency graph may have unknown dependencies. It is recommended that implementations assume this to be opaque and not an indicator of an object being dependency-free. It is recommended to leverage compositions to indicate unknown dependency graphs.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// References a component or service by its bom-ref attribute
ref: []const u8,
/// The bom-ref identifiers of the components or services that are dependencies of this dependency object.
dependsOn: ?[][]const u8 = null,
/// The bom-ref identifiers of the components or services that define a given specification or standard, which are provided or implemented by this dependency object. For example, a cryptographic library which implements a cryptographic algorithm. A component which implements another component does not imply that the implementation is in use.
provides: ?[][]const u8 = null,

pub fn new(ref: []const u8, allocator: Allocator) !@This() {
    return .{
        .ref = try allocator.dupe(u8, ref),
    };
}

pub fn addDependency(self: *@This(), ref: []const u8, allocator: Allocator) !void {
    self.dependsOn = if (self.dependsOn == null)
        try allocator.alloc([]const u8, 1)
    else
        try allocator.realloc(self.dependsOn.?, self.dependsOn.?.len + 1);

    self.dependsOn.?[self.dependsOn.?.len - 1] = try allocator.dupe(u8, ref);
}

pub fn deinit(self: *const @This(), allocator: Allocator) void {
    allocator.free(self.ref);
    if (self.dependsOn) |do| {
        for (do) |d| allocator.free(d);
        allocator.free(do);
    }
    if (self.provides) |pv| {
        for (pv) |d| allocator.free(d);
        allocator.free(pv);
    }
}
