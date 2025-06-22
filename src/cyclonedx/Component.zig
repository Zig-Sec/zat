//! The component that the BOM describes.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Supplier = @import("Supplier.zig");
const ExternalReference = @import("ExternalReference.zig");

/// Specifies the type of component. For software components, classify as
/// application if no more specific appropriate classification is available
/// or cannot be determined for the component.
type: Type,

/// An optional identifier which can be used to reference the component elsewhere
/// in the BOM. Every bom-ref must be unique within the BOM.
///
/// For Zig applications, modules and libraries, the fingerprint is used as a reference.
@"bom-ref": ?[]const u8 = null,
/// The organization that supplied the component. The supplier may often be the
/// manufacturer, but may also be a distributor or repackager.
supplier: ?Supplier = null,
/// The organization that created the component.
/// Manufacturer is common in components created through automated processes.
/// Components created through manual means may have authors instead.
manufacturer: ?Supplier = null,
/// The name of the component. This will often be a shortened, single name of the
/// component. Examples: commons-lang3 and jquery
name: []const u8,
/// The component version.
version: ?[]const u8 = null,
/// Asserts the identity of the component using package-url (purl). The purl, if specified, must be valid and conform to the specification defined at: https://github.com/package-url/purl-spec. Refer to @.evidence.identity to optionally provide evidence that substantiates the assertion of the component's identity.
purl: ?[]const u8 = null,
/// External references provide a way to document systems, sites, and information
/// that may be relevant but are not included with the BOM. They may also establish
/// specific relationships within or external to the BOM.
externalReferences: ?[]const ExternalReference = null,
/// A list of software and hardware components included in the parent component.
/// This is not a dependency tree. It provides a way to specify a hierarchical
/// representation of component assemblies, similar to system → subsystem → parts assembly
/// in physical supply chains.
components: ?[]const @This() = null,
/// Provides the ability to document properties in a name-value store. This
/// provides flexibility to include data not officially supported in the
/// standard without having to use additional namespaces or create extensions.
/// Unlike key-value stores, properties support duplicate names, each potentially
/// having different values. Property names of interest to the general public are
/// encouraged to be registered in the CycloneDX Property Taxonomy. Formal
/// registration is optional.
properties: ?[]const Property = null,

/// Provides the ability to document properties in a name-value store.
/// This provides flexibility to include data not officially supported
/// in the standard without having to use additional namespaces or create
/// extensions. Unlike key-value stores, properties support duplicate names,
/// each potentially having different values. Property names of interest to
/// the general public are encouraged to be registered in the CycloneDX
/// Property Taxonomy. Formal registration is optional.
pub const Property = struct {
    /// The name of the property. Duplicate names are allowed, each potentially
    /// having a different value.
    name: []const u8,
    /// The value of the property.
    value: ?[]const u8,

    pub fn deinit(self: *const @This(), allocator: Allocator) void {
        allocator.free(self.name);
        if (self.value) |v| allocator.free(v);
    }

    pub fn newPackageHash(hash: []const u8, allocator: Allocator) !@This() {
        const name = try allocator.dupe(u8, "zig:package_hash");
        errdefer allocator.free(name);

        const value = try allocator.dupe(u8, hash);
        errdefer allocator.free(value);

        return .{
            .name = name,
            .value = value,
        };
    }
};

pub const Type = enum {
    application,
    framework,
    library,
    container,
    platform,
    @"operating-system",
    device,
    @"device-driver",
    firmware,
    file,
    @"machine-learning-model",
    data,
    @"cryptographic-asset",
};

pub fn deinit(self: *const @This(), allocator: Allocator) void {
    if (self.@"bom-ref") |ref| allocator.free(ref);
    if (self.supplier) |sup| sup.deinit(allocator);
    if (self.manufacturer) |sup| sup.deinit(allocator);
    allocator.free(self.name);
    if (self.version) |v| allocator.free(v);
    if (self.purl) |v| allocator.free(v);
    if (self.externalReferences) |refs| {
        for (refs) |ref| ref.deinit(allocator);
        allocator.free(refs);
    }
    if (self.components) |comps| {
        for (comps) |comp| comp.deinit(allocator);
        allocator.free(comps);
    }
    if (self.properties) |props| {
        for (props) |prop| prop.deinit(allocator);
        allocator.free(props);
    }
}
