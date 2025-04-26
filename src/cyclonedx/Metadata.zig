const std = @import("std");
const Allocator = std.mem.Allocator;

const Component = @import("Component.zig");

/// The tool(s) used in the creation, enrichment, and validation of the BOM.
tools: ?struct {
    components: ?[]const Component = null,
} = null,
/// The component that the BOM describes.
component: ?Component = null,

pub fn deinit(self: *const @This(), allocator: Allocator) void {
    if (self.tools) |tools| {
        if (tools.components) |comps| {
            for (comps) |tool| tool.deinit(allocator);
            allocator.free(comps);
        }
    }
    if (self.component) |comp| comp.deinit(allocator);
}
