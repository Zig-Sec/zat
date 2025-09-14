pub const graph = @import("cmd/graph.zig");
pub const sbom = @import("cmd/sbom.zig");
pub const github_dependency = @import("cmd/github_dependency.zig");

test {
    _ = graph;
    _ = sbom;
    _ = github_dependency;
}
