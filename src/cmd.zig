pub const graph = @import("cmd/graph.zig");
pub const sbom = @import("cmd/sbom.zig");
pub const github_dependency = @import("cmd/github_dependency.zig");
pub const scan = @import("cmd/scan.zig");

test {
    _ = graph;
    _ = sbom;
    _ = github_dependency;
    _ = scan;
}
