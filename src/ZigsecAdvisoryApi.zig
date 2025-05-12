//! This container provides all functionality for accessing the Zig-Sec/advisory-db database on Github.
//!
//! - Use `fetchAdvisories` to fetch advisories for a specific package.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Advisory = @import("advisory").Advisory;

const fingerprint_url_template = "https://api.github.com/repos/Zig-Sec/advisory-db/contents/packages/{s}";

const FileResponse = []const FileDescriptor;

const Advisories = []const Advisory;

const FileDescriptor = struct {
    name: []const u8,
    url: []const u8,

    pub fn deinit(self: *const @This(), allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.url);
    }
};

const File = struct {
    content: []const u8,
    encoding: []const u8,
    html_url: []const u8,

    pub fn deinit(self: *const @This(), allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.encoding);
        allocator.free(self.html_url);
    }
};

/// Fetch all advisories for a given package.
///
/// * `client` - A HTTP Client used to connect to the database
/// * `fp` - A fingerprint used to uniquely identify the package
/// * `allocator` - An allocator for allocating memory
///
/// # Returns
///
/// A slice of advisories.
pub fn fetchAdvisories(
    client: *std.http.Client,
    name: []const u8,
    allocator: Allocator,
) !Advisories {
    var advisories = std.ArrayList(Advisory).init(allocator);
    errdefer {
        for (advisories.items) |adv| adv.deinit(allocator);
        advisories.deinit();
    }

    // First check if advisories exist for the given fingerprint fp.
    var response_body = std.ArrayList(u8).init(allocator);
    defer response_body.deinit();

    const fingerprint_url = try std.fmt.allocPrint(
        allocator,
        fingerprint_url_template,
        .{name},
    );
    defer allocator.free(fingerprint_url);

    _ = try client.fetch(.{
        .headers = .{
            .accept_encoding = .{ .override = "application/vnd.github+json" },
        },
        .method = .GET,
        .location = .{ .url = fingerprint_url },
        .response_storage = .{
            .dynamic = &response_body,
        },
    });

    const files = try std.json.parseFromSliceLeaky(
        FileResponse,
        allocator,
        response_body.items,
        .{
            .ignore_unknown_fields = true,
        },
    );

    // Now fetch every advisory
    for (files) |file| {
        var response_body2 = std.ArrayList(u8).init(allocator);
        defer response_body2.deinit();

        _ = try client.fetch(.{
            .headers = .{
                .accept_encoding = .{ .override = "application/vnd.github+json" },
            },
            .method = .GET,
            .location = .{ .url = file.url },
            .response_storage = .{
                .dynamic = &response_body2,
            },
        });

        const advisory_file = std.json.parseFromSliceLeaky(
            File,
            allocator,
            response_body2.items,
            .{
                .ignore_unknown_fields = true,
            },
        ) catch |e| {
            std.log.err("unable to parse '{s}' advisory file ({any})! Please consider reporting this as an issue.", .{ file.name, e });
            continue;
        };

        var b64 = std.ArrayList(u8).init(allocator);
        defer b64.deinit();
        var iter = std.mem.splitAny(u8, advisory_file.content, "\n");
        while (iter.next()) |chunk| try b64.appendSlice(chunk);

        const l = std.base64.standard.Decoder.calcSizeForSlice(b64.items) catch |e| {
            std.log.err("unable to calc size for bas64 string ({any})\n", .{e});
            continue;
        };
        const dest = try allocator.alloc(u8, l);
        defer allocator.free(dest);

        std.base64.standard.Decoder.decode(dest, b64.items) catch |e| {
            std.log.err("unable to decode base64 ({any})\n", .{e});
            continue;
        };

        const s = try allocator.dupeZ(u8, dest);
        defer allocator.free(s);

        const package_advisory = try std.zon.parse.fromSlice(
            Advisory,
            allocator,
            s,
            null,
            .{ .ignore_unknown_fields = true },
        );

        try advisories.append(package_advisory);
    }

    return try advisories.toOwnedSlice();
}
