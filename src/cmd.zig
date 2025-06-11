pub const graph = @import("cmd/graph.zig");
pub const audit = @import("cmd/audit.zig");
pub const sbom = @import("cmd/sbom.zig");
pub const inspect_build = @import("cmd/inspect_build.zig");

test {
    _ = audit;
    _ = graph;
    _ = sbom;
    _ = inspect_build;
}
