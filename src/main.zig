const std = @import("std");
const clap = @import("clap");

const root = @import("root.zig");

var stdout_buffer: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

var stderr_buffer: [1024]u8 = undefined;
var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
const stderr = &stderr_writer.interface;

var stdin_buffer: [1024]u8 = undefined;
const stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
const stdin = stdin_reader.interface;

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
        \\--inspect-build          Inspect the components defined by the build script
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
        diag.report(stderr, err) catch {};
        return;
    };
    defer res.deinit();

    if (res.args.audit != 0) {
        //try root.cmd.audit.cmdAudit(allocator, arena, res.args);
    } else if (res.args.release != 0) {
        //try root.release.cmdNewRelease(allocator, arena, res.args);
    } else if (res.args.graph != 0) {
        try root.cmd.graph.cmdGraph(
            allocator,
            arena,
            res.args,
            stdout,
            stderr,
        );
    } else if (res.args.sbom != 0) {
        try root.cmd.sbom.cmdSbom(
            allocator,
            arena,
            res.args,
            stdout,
            stderr,
        );
    } else if (res.args.@"inspect-build" != 0) {
        //try root.cmd.inspect_build.cmdIntrospect(allocator, arena, res.args);
    } else {
        try stdout.print(help_text, .{});
        return;
    }

    try stdout.flush();
    try stderr.flush();
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
    \\ --inspect-build                             Inspect the components of the build script
    \\
    \\Options:
    \\ -y                                          Accept all
    \\
    \\Graph Options
    \\ --mermaid                                   Create a mermaid graph (supported by Github READMEs)
    \\ --path <str>                                The file to write the graph to
    \\
    \\SBOM Options
    \\ --cyclonedx-json                            Create a CycloneDX SBOM using the Json format (default)
    \\
    \\
;
