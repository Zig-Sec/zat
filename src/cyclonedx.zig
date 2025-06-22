const std = @import("std");
const Allocator = std.mem.Allocator;

const PackageInfo = @import("PackageInfo.zig");

/// Specifies the format of the BOM. This helps to identify the file as
/// CycloneDX since BOMs do not have a filename convention, nor does JSON
/// schema support namespaces. This value must be "CycloneDX".
pub const BomFormat = "CycloneDX";

/// The version of the CycloneDX specification the BOM conforms to.
pub const SpecVersion = "1.6";

pub const SerialNumber = @import("cyclonedx/SerialNumber.zig");

/// Whenever an existing BOM is modified, either manually or through
/// automated processes, the version of the BOM SHOULD be incremented
/// by 1. When a system is presented with multiple BOMs with identical
/// serial numbers, the system SHOULD use the most recent version of
/// the BOM. The default version is '1'.
pub const Version = usize;

pub const Metadata = @import("cyclonedx/Metadata.zig");

pub const Component = @import("cyclonedx/Component.zig");

pub const Supplier = @import("cyclonedx/Supplier.zig");

pub const ExternalReference = @import("cyclonedx/ExternalReference.zig");

pub const Dependency = @import("cyclonedx/Dependency.zig");

pub const SBOM = struct {
    /// Specifies the format of the BOM. This helps to identify the file as CycloneDX since BOMs do not have a filename convention, nor does JSON schema support namespaces. This value must be "CycloneDX".
    bomFormat: []const u8 = BomFormat,
    /// The version of the CycloneDX specification the BOM conforms to.
    specVersion: []const u8 = SpecVersion,
    serialNumber: SerialNumber.SerialNumber,
    version: Version = 1,
    metadata: ?Metadata = null,
    components: ?[]Component = null,
    dependencies: ?[]Dependency = null,

    pub fn new(allocator: Allocator) !@This() {
        _ = allocator;

        const sbom = @This(){
            .serialNumber = SerialNumber.new(),
        };

        return sbom;
    }

    pub fn deinit(self: *const @This(), allocator: Allocator) void {
        if (self.metadata) |meta| meta.deinit(allocator);
        if (self.components) |comps| {
            for (comps) |comp| comp.deinit(allocator);
            allocator.free(comps);
        }
        if (self.dependencies) |deps| {
            for (deps) |dep| dep.deinit(allocator);
            allocator.free(deps);
        }
    }

    pub fn addComponent(self: *@This(), comp: Component, allocator: Allocator) !void {
        if (self.components == null)
            self.components = try allocator.alloc(Component, 1)
        else
            self.components = try allocator.realloc(self.components.?, self.components.?.len + 1);

        self.components.?[self.components.?.len - 1] = comp;
    }

    pub fn addDependency(self: *@This(), dep: Dependency, allocator: Allocator) !void {
        if (self.dependencies == null)
            self.dependencies = try allocator.alloc(Dependency, 1)
        else
            self.dependencies = try allocator.realloc(self.dependencies.?, self.dependencies.?.len + 1);

        self.dependencies.?[self.dependencies.?.len - 1] = dep;
    }
};

pub fn componentFromPackageInfo(
    allocator: Allocator,
    pi: *const PackageInfo,
    map: *const PackageInfo.PackageInfoMap,
    t: ?Component.Type,
) !struct { Component, Dependency } {
    // Make Component for Package
    const name = try allocator.dupe(u8, pi.name);
    errdefer allocator.free(name);

    var extrefs = try allocator.alloc(ExternalReference, 0);
    errdefer allocator.free(extrefs);

    var purl: ?[]const u8 = null;

    if (!std.mem.eql(u8, "", pi.url)) {
        // Define purl based on url
        // TODO: currently only works with git
        purl = purlFromUrl(pi.url, allocator, pi.sversion) catch null;

        // Add external reference to the package
        const l = extrefs.len;

        const package_ref = try allocator.dupe(u8, pi.url);
        errdefer allocator.free(package_ref);

        extrefs = try allocator.realloc(extrefs, l + 1);

        extrefs[l] = .{
            .url = package_ref,
            .type = .vcs,
        };
    }

    // Create Dependency for package
    var dependency = try Dependency.new(pi.ref, allocator);
    errdefer dependency.deinit(allocator);

    for (pi.children.items) |dep_fp| {
        const dep = map.get(dep_fp).?;
        try dependency.addDependency(dep.ref, allocator);
    }

    // Set properties
    var properties = std.ArrayList(Component.Property).init(allocator);
    defer if (properties.items.len == 0) properties.deinit();

    if (pi.hash.len > 0) {
        try properties.append(try Component.Property.newPackageHash(pi.hash, allocator));
    }

    return .{
        .{
            .type = if (t) |t_| t_ else .application,
            .@"bom-ref" = try allocator.dupe(u8, pi.ref),
            .name = name,
            .version = try allocator.dupe(u8, pi.sversion),
            .purl = purl,
            .externalReferences = if (extrefs.len == 0) null else extrefs,
            .properties = if (properties.items.len == 0) null else try properties.toOwnedSlice(),
        },
        dependency,
    };
}

/// Create a Component that represents the Zig Audit Tool.
/// This component can be added as a tool to the meta-data of the SBOM.
pub fn makeZatToolComponent(allocator: Allocator) !Component {
    const manu = try Supplier.new1(allocator, "Zig-Sec", "https://zigsec.org/");
    errdefer manu.deinit(allocator);

    const name = try allocator.dupe(u8, "zat");
    errdefer allocator.free(name);

    const extref_url = try allocator.dupe(u8, "https://github.com/Zig-Sec/zat");
    errdefer allocator.free(extref_url);

    const extrefs = try allocator.alloc(ExternalReference, 1);
    errdefer allocator.free(extrefs);
    extrefs[0] = .{
        .url = extref_url,
        .type = .vcs,
    };

    return .{
        .type = .application,
        .manufacturer = manu,
        .name = name,
        .externalReferences = extrefs,
    };
}

pub fn purlFromUrl(url: []const u8, allocator: Allocator, version_string: ?[]const u8) ![]const u8 {
    if (std.mem.indexOf(u8, url, "github")) |idx| {
        return gitPurlFromUrl(url, allocator, version_string, idx, "github");
    } else if (std.mem.indexOf(u8, url, "gitea")) |idx| {
        return gitPurlFromUrl(url, allocator, version_string, idx, "gitea");
    } else if (std.mem.indexOf(u8, url, "gitlab")) |idx| {
        return gitPurlFromUrl(url, allocator, version_string, idx, "gitlab");
    } else {
        return error.UnsupportedCandidateType;
    }
}

fn gitPurlFromUrl(url: []const u8, allocator: Allocator, version_string: ?[]const u8, idx: usize, vcs: []const u8) ![]const u8 {
    if (std.mem.containsAtLeast(u8, url, 1, "http")) {
        var begin = idx;
        while (begin < url.len and url[begin] != '/') begin += 1;

        var end = begin + 1;
        var count: u8 = 0;
        while (end < url.len) {
            if (url[end] == '/') {
                if (count > 0) break;
                count += 1;
            }
            end += 1;
        }
        // pkg:github/package-url/purl-spec@244fd47e07d1004f0aed9c
        return std.fmt.allocPrint(
            allocator,
            "pkg:{s}{s}{s}{s}",
            .{
                vcs,
                url[begin..end],
                if (version_string) |_| "@" else "",
                if (version_string) |v| v else "",
            },
        );
    } else { // assume ssh
        var begin1: usize = idx;
        while (begin1 < url.len and url[begin1 - 1] != ':') begin1 += 1;

        var end1 = begin1 + 1;
        while (end1 < url.len and url[end1] != '.') end1 += 1;

        return std.fmt.allocPrint(
            allocator,
            "pkg:{s}/{s}{s}{s}",
            .{
                vcs,
                url[begin1..end1],
                if (version_string) |_| "@" else "",
                if (version_string) |v| v else "",
            },
        );
    }
}

test {
    _ = Metadata;
    _ = Component;
    _ = Supplier;
    _ = ExternalReference;
    _ = Dependency;
}
