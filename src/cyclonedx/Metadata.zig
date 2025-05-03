const std = @import("std");
const Allocator = std.mem.Allocator;

const Component = @import("Component.zig");

const time = @import("../time.zig");

/// The date and time (timestamp) when the BOM was created.
timestamp: []const u8,
/// The tool(s) used in the creation, enrichment, and validation of the BOM.
tools: ?struct {
    components: ?[]const Component = null,
} = null,
/// The component that the BOM describes.
component: ?Component = null,

pub fn deinit(self: *const @This(), allocator: Allocator) void {
    allocator.free(self.timestamp);
    if (self.tools) |tools| {
        if (tools.components) |comps| {
            for (comps) |tool| tool.deinit(allocator);
            allocator.free(comps);
        }
    }
    if (self.component) |comp| comp.deinit(allocator);
}
