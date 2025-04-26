//! The organization that supplied the component. The supplier may often be the manufacturer, but may also be a distributor or repackager.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Contact = @import("Contact.zig");

@"bom-ref": ?[]u8 = null,
/// The name of the organization.
name: []const u8,
/// The URL of the organization. Multiple URLs are allowed.
url: ?[]const []const u8 = null,
/// A contact at the organization. Multiple contacts are allowed.
contact: ?[]const Contact = null,

pub fn new1(allocator: Allocator, name: []const u8, url: []const u8) !@This() {
    const name_ = try allocator.dupe(u8, name);
    errdefer allocator.free(name_);

    const url_ = try allocator.dupe(u8, url);
    errdefer allocator.free(url_);

    const urls = try allocator.alloc([]const u8, 1);
    urls[0] = url_;

    return .{
        .name = name_,
        .url = urls,
    };
}

pub fn deinit(self: *const @This(), allocator: Allocator) void {
    if (self.@"bom-ref") |ref| allocator.free(ref);

    allocator.free(self.name);

    if (self.url) |urls| {
        for (urls) |url| allocator.free(url);
        allocator.free(urls);
    }

    if (self.contact) |contacts| {
        for (contacts) |contact| contact.deinit(allocator);
        allocator.free(contacts);
    }
}
