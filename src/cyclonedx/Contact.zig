//! A contact at the organization.

const std = @import("std");
const Allocator = std.mem.Allocator;

@"bom-ref": ?[]u8 = null,
name: []const u8,
email: []const u8,
phone: ?[]const u8,

pub fn deinit(self: *const @This(), allocator: Allocator) void {
    if (self.@"bom-ref") |ref| allocator.free(ref);
    allocator.free(self.name);
    allocator.free(self.email);
    if (self.phone) |phone| allocator.free(phone);
}
