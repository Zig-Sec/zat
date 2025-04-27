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

pub const SBOM = struct {
    /// Specifies the format of the BOM. This helps to identify the file as CycloneDX since BOMs do not have a filename convention, nor does JSON schema support namespaces. This value must be "CycloneDX".
    bomFormat: []const u8 = BomFormat,
    /// The version of the CycloneDX specification the BOM conforms to.
    specVersion: []const u8 = SpecVersion,
    serialNumber: SerialNumber.SerialNumber,
    version: Version = 1,
    metadata: ?Metadata = null,

    pub fn new(allocator: Allocator) !@This() {
        _ = allocator;

        const sbom = @This(){
            .serialNumber = SerialNumber.new(),
        };

        return sbom;
    }

    pub fn deinit(self: *const @This(), allocator: Allocator) void {
        if (self.metadata) |meta| meta.deinit(allocator);
    }
};

pub fn componentFromPackageInfo(allocator: Allocator, pi: *const PackageInfo) !Component {
    const name = try allocator.dupe(u8, pi.name);
    errdefer allocator.free(name);

    const version = try std.fmt.allocPrint(
        allocator,
        "{d}.{d}.{d}{s}{s}{s}{s}",
        .{
            pi.version.major,
            pi.version.minor,
            pi.version.patch,
            if (pi.version.pre) |_| "-" else "",
            if (pi.version.pre) |pre| pre else "",
            if (pi.version.build) |_| "+" else "",
            if (pi.version.build) |build| build else "",
        },
    );
    errdefer allocator.free(version);

    const bomref = try std.fmt.allocPrint(
        allocator,
        "{x}@{s}",
        .{ pi.fingerprint, version },
    );
    errdefer allocator.free(bomref);

    const package_ref = try allocator.dupe(u8, pi.url);
    errdefer allocator.free(package_ref);

    const extrefs = try allocator.alloc(ExternalReference, 1);
    errdefer allocator.free(extrefs);
    extrefs[0] = .{
        .url = package_ref,
        .type = .vcs,
    };

    return .{
        .type = .application,
        .@"bom-ref" = bomref,
        .name = name,
        .version = version,
        .externalReferences = extrefs,
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

test {
    _ = Metadata;
    _ = Component;
    _ = Supplier;
    _ = ExternalReference;
}
