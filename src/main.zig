const std = @import("std");
const clap = @import("clap");

const root = @import("root.zig");

const stdin = std.io.getStdIn();
const stdout = std.io.getStdOut();
const stderr = std.io.getStdErr();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var arena_instance = std.heap.ArenaAllocator.init(allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help               Display this help and exit.
        \\--audit                  Audit a package
        \\--release                Create a new release for a package
        \\--graph                  Create a dependency graph
        \\--introspect
        \\--major                  Major release
        \\--minor                  Minor release
        \\--patch                  Patch release
        \\-y                       Accept all changes
        \\--mermaid                Use the mermaid format
        \\--path <str>             Define a path
        \\--sbom                   Generate a SBOM for a package
        \\--cyclonedx-json         Create a CycloneDX SBOM using the Json format
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return;
    };
    defer res.deinit();

    if (res.args.audit != 0) {
        try root.cmd.audit.cmdAudit(allocator, arena, res.args);
    } else if (res.args.release != 0) {
        try root.release.cmdNewRelease(allocator, arena, res.args);
    } else if (res.args.graph != 0) {
        try root.cmd.graph.cmdGraph(allocator, arena, res.args);
    } else if (res.args.sbom != 0) {
        try root.cmd.sbom.cmdSbom(allocator, arena, res.args);
    } else if (res.args.introspect != 0) {
        try root.cmd.introspect.cmdIntrospect(allocator, arena, res.args);
    } else {
        try std.fmt.format(stdout.writer(), help_text, .{});
        return;
    }
}

const help_text =
    \\zat - Zig Audit Tool
    \\Copyright (C) 2025 Zig-Sec org. (https://github.com/Zig-Sec)
    \\Authors:
    \\ David P. Sugar (r4gus)
    \\License MIT <https://opensource.org/license/MIT>
    \\This is free software: you are free to change and redistribute it.
    \\There is NO WARRANTY, to the extent permitted by law.
    \\
    \\Syntax: zat [options]
    \\
    \\Commands:
    \\ -h, --help                                  Display this help and exit
    \\ --graph                                     Create a dependency graph
    \\ --audit                                     Audit the given package
    \\ --sbom                                      Generate a SBOM for a package
    \\
    \\Options:
    \\ -y                                          Accept all
    \\
    \\Release Options
    \\ --major                                     Create a major release
    \\ --minor                                     Create a minor release
    \\ --patch                                     Create a patch release
    \\
    \\Graph Options
    \\ --mermaid                                   Create a mermaid graph (supported by Github READMEs)
    \\ --path <str>                                The file to write the graph to
    \\
    \\SBOM Options
    \\ --cyclonedx-json                            Create a CycloneDX SBOM using the Json format (default)
    \\
;
