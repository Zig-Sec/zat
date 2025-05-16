pub const graph = @import("cmd/graph.zig");
pub const audit = @import("cmd/audit.zig");
pub const sbom = @import("cmd/sbom.zig");
pub const introspect = @import("cmd/introspect.zig");

test {
    _ = audit;
    _ = graph;
    _ = sbom;
    _ = introspect;
}
