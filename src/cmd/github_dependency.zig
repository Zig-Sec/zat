const std = @import("std");
const Allocator = std.mem.Allocator;
const fatal = std.process.fatal;

const sbom = @import("sbom.zig");

pub fn cmdSbom(
    allocator: Allocator,
    arena: Allocator,
    args: anytype,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !void {
    _ = stderr;

    const minify = if (args.minify != 0) true else false;
    const jobid = if (args.jobid) |v| v else "zat";
    const correlator = if (args.correlator) |v| v else "zat";
    const sha = if (args.sha) |v| v else {
        fatal("sha required for Github manifest. provide it with --sha=<sha>", .{});
    };
    const ref = if (args.ref) |v| v else {
        fatal("ref required for Github manifest. provide it with --ref=<ref>", .{});
    };

    var root_prog_node = std.Progress.start(.{
        .root_name = "generate Github dependency submission",
    });

    const bom = try sbom.createSbom(
        allocator,
        arena,
        root_prog_node,
        false,
    );
    defer bom.deinit(allocator);

    var raw = std.Io.Writer.Allocating.init(allocator);
    defer raw.deinit();

    var json: std.json.Stringify = .{
        .writer = &raw.writer,
        .options = .{
            .whitespace = if (minify) .minified else .indent_4,
        },
    };
    try json.beginObject();
    {
        try json.objectField("version");
        try json.print("{d}", .{0});

        try json.objectField("job");
        try json.beginObject();
        {
            try json.objectField("id");
            try json.write(jobid);

            try json.objectField("correlator");
            try json.write(correlator);
        }
        try json.endObject();

        try json.objectField("sha");
        try json.write(sha);

        try json.objectField("ref");
        try json.write(ref);

        try json.objectField("detector");
        try json.beginObject();
        {
            try json.objectField("name");
            try json.write("zat");

            try json.objectField("version");
            try json.write("0.2.0");

            try json.objectField("url");
            try json.write("https://github.com/Zig-Sec/zat");
        }
        try json.endObject();

        try json.objectField("manifests");
        try json.beginObject();
        {
            try json.objectField("build.zig.zon");
            try json.beginObject();
            {
                try json.objectField("name");
                try json.write("build.zig.zon");

                try json.objectField("file");
                try json.beginObject();
                {
                    try json.objectField("source_location");
                    try json.write("build.zig.zon");
                }
                try json.endObject();

                try json.objectField("resolved");
                try json.beginObject();
                {
                    if (bom.components) |comps| {
                        for (comps) |comp| {
                            try json.objectField(comp.name);
                            try json.beginObject();
                            {
                                if (comp.purl) |purl| {
                                    try json.objectField("package_url");
                                    try json.write(purl);
                                }
                            }
                            try json.endObject();
                        }
                    }
                }
                try json.endObject();
            }
            try json.endObject();
        }
        try json.endObject();

        try json.objectField("scanned");
        try json.write(bom.metadata.?.timestamp);
    }
    try json.endObject();

    root_prog_node.end(); // this comes right before writing...

    try stdout.print("{s}\n", .{raw.written()});
}
