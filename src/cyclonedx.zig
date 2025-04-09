const std = @import("std");
const Allocator = std.mem.Allocator;
const uuid = @import("uuid");

pub const CycloneDX = struct {
    /// Specifies the format of the BOM. This helps to identify
    /// the file as CycloneDX since BOMs do not have a filename
    /// convention, nor does JSON schema support namespaces.
    bomFormat: []const u8 = "CycloneDX",
    /// The version of the CycloneDX specification the BOM conforms to.
    specVersion: []const u8 = "1.6",
    /// Every BOM generated SHOULD have a unique serial number, even if
    /// the contents of the BOM have not changed over time. If specified,
    /// the serial number must conform to RFC 4122. Use of serial numbers
    /// is recommended.
    serialNumber: [45]u8,
    /// Whenever an existing BOM is modified, either manually or through
    /// automated processes, the version of the BOM SHOULD be incremented
    /// by 1. When a system is presented with multiple BOMs with identical
    /// serial numbers, the system SHOULD use the most recent version of the
    /// BOM. The default version is '1'.
    version: usize = 1,
    /// Provides additional information about a BOM.
    metadata: struct {
        /// The tool(s) used in the creation, enrichment, and validation of the BOM.
        tools: ?[]const Component = null,
        /// The component that the BOM describes.
        component: ?Component = null,

        pub fn deinit(self: *const @This(), allocator: Allocator) void {
            if (self.component) |component| component.deinit(allocator);
        }

        pub fn addComponent(
            self: *@This(),
            component: Component,
            allocator: Allocator,
        ) !void {
            if (self.component) |comp| comp.deinit(allocator);

            self.component = component;

            var parent: *CycloneDX = @fieldParentPtr("metadata", self);

            if (self.component.?.@"bom-ref") |ref| {
                try parent.addDependency(.{
                    .ref = try allocator.dupe(u8, ref),
                }, allocator);
            }
        }
    } = .{},
    /// A list of software and hardware components.
    components: ?[]Component = null,
    /// Provides the ability to document dependency relationships including
    /// provided & implemented components.
    dependencies: ?[]Dependency = null,

    pub const Dependency = struct {
        /// References a component or service by its bom-ref attribute.
        ref: []const u8,
        /// The bom-ref identifiers of the components or services that are
        /// dependencies of this dependency object.
        dependsOn: ?[][]const u8 = null,
        provides: ?[][]const u8 = null,

        pub fn deinit(self: *const @This(), allocator: Allocator) void {
            allocator.free(self.ref);

            if (self.dependsOn) |deps| {
                for (deps) |dep| allocator.free(dep);
                allocator.free(deps);
            }

            if (self.provides) |provisions| {
                for (provisions) |obj| allocator.free(obj);
                allocator.free(provisions);
            }
        }
    };

    pub const Component = struct {
        /// Specifies the type of component.
        type: Type,
        /// The optional mime-type of the component. When used on file components,
        /// the mime-type can provide additional context about the kind of file
        /// being represented, such as an image, font, or executable. Some library
        /// or framework components may also have an associated mime-type.
        @"mime-type": ?[]const u8 = null,
        /// An optional identifier which can be used to reference the component
        /// elsewhere in the BOM. Every bom-ref must be unique within the BOM.
        /// Value SHOULD not start with the BOM-Link intro 'urn:cdx:' to avoid
        /// conflicts with BOM-Links.
        @"bom-ref": ?[]const u8 = null,
        /// The person(s) who created the component. Authors are common in
        /// components created through manual processes.
        authors: ?[]Author = null,
        /// The person(s) or organization(s) that published the component.
        publisher: ?[]const u8 = null,
        /// The grouping name or identifier. This will often be a shortened,
        /// single name of the company or project that produced the component,
        /// or the source package or domain name. Whitespace and special characters
        /// should be avoided. Examples include: apache, org.apache.commons,
        /// and apache.org.
        group: ?[]const u8 = null,
        /// The name of the component. This will often be a shortened, single
        /// name of the component. Examples: commons-lang3 and jquery.
        name: []const u8,
        /// The component version. The version should ideally comply with semantic
        /// versioning but is not enforced.
        version: ?[]const u8 = null,
        /// Specifies a description for the component.
        description: ?[]const u8 = null,
        /// Specifies the scope of the component. If scope is not specified,
        /// 'required' scope SHOULD be assumed by the consumer of the BOM.
        scope: ?Scope = null,
        /// The hashes of the component.
        hashes: ?[]const Hash = null,
        /// A list of software and hardware components included in the parent
        /// component. This is not a dependency tree. It provides a way to
        /// specify a hierarchical representation of component assemblies,
        /// similar to system → subsystem → parts assembly in physical supply chains.
        ///
        /// For Zig this could mean a project consisting of a build.zig,
        /// build.zig.zon, and corresponding source code, where build.zig
        /// defines multiple executables, modules, or libraries, e.g.: a
        /// a KDBX repository that consists of a library and an command line
        /// application to manipulate KDBX files.
        components: ?[]const @This() = null,
        /// External references provide a way to document systems, sites, and
        /// information that may be relevant but are not included with the BOM.
        /// They may also establish specific relationships within or external
        /// to the BOM.
        externalReferences: ?[]Reference = null,

        pub const Reference = struct {
            /// The URI (URL or URN) to the external reference. External references
            /// are URIs and therefore can accept any URL scheme including https
            /// (RFC-7230), mailto (RFC-2368), tel (RFC-3966), and dns (RFC-4501).
            /// External references may also include formally registered URNs such
            /// as CycloneDX BOM-Link to reference CycloneDX BOMs or any object within
            /// a BOM. BOM-Link transforms applicable external references into
            /// relationships that can be expressed in a BOM or across BOMs.
            url: []const u8,
            /// An optional comment describing the external reference.
            comment: ?[]const u8 = null,
            /// Specifies the type of external reference.
            type: @This().Type,

            pub const Type = enum {
                /// Version Control System (e.g. Git)
                vcs,
                @"issue-tracker",
                website,
                advisories,
                bom,
                @"mailing-list",
                social,
                chat,
                documentation,
                support,
                @"source-distribution",
                distribution,
                @"distribution-intake",
                license,
                @"build-meta",
                @"build-system",
                @"release-notes",
                @"security-contact",
                @"model-card",
                log,
                configuration,
                evidence,
                formulation,
                attestation,
                @"threat-model",
                @"adversary-model",
                @"risk-assessment",
                @"vulnerability-assertion",
                @"exploitability-statement",
                @"pentest-report",
                @"static-analysis-report",
                @"dynamic-analysis-report",
                @"runtime-analysis-report",
                @"component-analysis-report",
                @"maturity-report",
                @"certification-report",
                @"codified-infrastructure",
                @"quality-metrics",
                poam,
                @"electronic-signature",
                @"rfc-9116",
                other,
            };

            pub fn deinit(self: *const @This(), allocator: Allocator) void {
                allocator.free(self.url);
                if (self.comment) |d| allocator.free(d);
            }

            pub fn clone(self: *const @This(), allocator: Allocator) !@This() {
                const url = try allocator.dupe(u8, self.url);
                errdefer allocator.free(url);
                const comment = if (self.comment) |br| try allocator.dupe(u8, br) else null;
                errdefer if (comment) |br| allocator.free(br);

                return .{
                    .url = url,
                    .comment = comment,
                    .type = self.type,
                };
            }
        };

        /// Specifies the type of component. For software components, classify
        /// as application if no more specific appropriate classification is
        /// available or cannot be determined for the component.
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

        pub const Author = struct {
            @"bom-ref": ?[]const u8 = null,
            /// The name of a contact
            name: ?[]const u8 = null,
            /// The email address of the contact.
            email: ?[]const u8 = null,
            /// The phone number of the contact.
            phone: ?[]const u8 = null,

            pub fn deinit(self: *const @This(), allocator: Allocator) void {
                if (self.@"bom-ref") |d| allocator.free(d);
                if (self.name) |d| allocator.free(d);
                if (self.email) |d| allocator.free(d);
                if (self.phone) |d| allocator.free(d);
            }

            pub fn clone(self: *const @This(), allocator: Allocator) !@This() {
                const @"bom-ref" = if (self.@"bom-ref") |br| try allocator.dupe(u8, br) else null;
                errdefer if (@"bom-ref") |br| allocator.free(br);
                const name = if (self.name) |br| try allocator.dupe(u8, br) else null;
                errdefer if (name) |br| allocator.free(br);
                const email = if (self.email) |br| try allocator.dupe(u8, br) else null;
                errdefer if (email) |br| allocator.free(br);
                const phone = if (self.phone) |br| try allocator.dupe(u8, br) else null;
                errdefer if (phone) |br| allocator.free(br);

                return .{
                    .@"bom-ref" = @"bom-ref",
                    .name = name,
                    .email = email,
                    .phone = phone,
                };
            }
        };

        pub const Scope = enum {
            /// The component is required for runtime.
            required,
            /// The component is optional at runtime. Optional components are
            /// components that are not capable of being called due to them not
            /// being installed or otherwise accessible by any means. Components
            /// that are installed but due to configuration or other restrictions
            /// are prohibited from being called must be scoped as 'required'.
            optional,
            /// Components that are excluded provide the ability to document component
            /// usage for test and other non-runtime purposes. Excluded components are
            /// not reachable within a call graph at runtime.
            excluded,
        };

        pub const Hash = struct {
            /// The algorithm that generated the hash value.
            alg: Alg,
            /// The value of the hash as hex-string.
            content: []const u8,

            pub const Alg = enum {
                MD5,
                @"SHA-1",
                @"SHA-256",
                @"SHA-384",
                @"SHA-512",
                @"SHA3-256",
                @"SHA3-384",
                @"SHA3-512",
                @"BLAKE2b-256",
                @"BLAKE2b-384",
                @"BLAKE2b-512",
                BLAKE3,
            };

            pub fn deinit(self: *const @This(), allocator: Allocator) void {
                allocator.free(self.content);
            }
        };

        pub fn deinit(self: *const @This(), allocator: Allocator) void {
            if (self.@"mime-type") |d| allocator.free(d);
            if (self.@"bom-ref") |d| allocator.free(d);
            if (self.authors) |authors| {
                for (authors) |author| author.deinit(allocator);
                allocator.free(authors);
            }
            if (self.publisher) |d| allocator.free(d);
            if (self.group) |d| allocator.free(d);
            allocator.free(self.name);
            if (self.version) |d| allocator.free(d);
            if (self.description) |d| allocator.free(d);
            if (self.hashes) |hashes| {
                for (hashes) |hash| hash.deinit(allocator);
                allocator.free(hashes);
            }
            if (self.components) |components| {
                for (components) |component| component.deinit(allocator);
                allocator.free(components);
            }
        }

        pub fn new(@"type": Type, name: []const u8, allocator: Allocator) !@This() {
            return .{
                .type = @"type",
                .name = try allocator.dupe(u8, name),
            };
        }

        pub fn setVersionFromCompileStep(
            self: *@This(),
            target: *std.Build.Step.Compile,
            allocator: Allocator,
        ) !void {
            self.version = if (target.version) |v|
                try std.fmt.allocPrint(
                    allocator,
                    "{d}.{d}.{d}",
                    .{ v.major, v.minor, v.patch },
                )
            else
                null;
        }

        pub fn setVersion(
            self: *@This(),
            v: []const u8,
            allocator: Allocator,
        ) !void {
            self.version = try allocator.dupe(u8, v);
        }

        pub fn setGroup(self: *@This(), group: []const u8, allocator: Allocator) !void {
            self.group = try allocator.dupe(u8, group);
        }

        pub fn setDescription(self: *@This(), desc: []const u8, allocator: Allocator) !void {
            self.description = try allocator.dupe(u8, desc);
        }

        pub fn generateBomRef(
            self: *@This(),
            alt: []const []const u8,
            allocator: Allocator,
        ) !void {
            var bom_ref = std.ArrayList(u8).init(allocator);
            errdefer bom_ref.deinit();

            if (self.group) |group| {
                try bom_ref.appendSlice(group);
                try bom_ref.append('/');
            }

            for (alt) |a| {
                try bom_ref.appendSlice(a);
                try bom_ref.append('/');
            }

            try bom_ref.appendSlice(self.name);

            if (self.version) |v| {
                try bom_ref.append('-');
                try bom_ref.appendSlice(v);
            }

            self.@"bom-ref" = try bom_ref.toOwnedSlice();
        }

        pub fn setComponents(self: *@This(), comps: []const @This()) void {
            self.components = comps;
        }

        pub fn addAuthor(self: *@This(), author: Author, allocator: Allocator) !void {
            var authors = if (self.authors) |authors|
                std.ArrayList(Author).fromOwnedSlice(allocator, authors)
            else
                std.ArrayList(Author).init(allocator);
            try authors.append(author);
            self.authors = try authors.toOwnedSlice();
        }

        pub fn addExternalReference(self: *@This(), reference: Reference, allocator: Allocator) !void {
            var references = if (self.externalReferences) |references|
                std.ArrayList(Reference).fromOwnedSlice(allocator, references)
            else
                std.ArrayList(Reference).init(allocator);
            try references.append(reference);
            self.externalReferences = references.toOwnedSlice() catch blk: {
                for (references.items) |ref| ref.deinit(allocator);
                references.deinit();
                break :blk null;
            };
        }
    };

    pub fn new(allocator: Allocator) !@This() {
        var serialNumber: [45]u8 = .{0} ** 45;
        const id = uuid.v4.new();
        const urn = uuid.urn.serialize(id);
        @memcpy(serialNumber[0..9], "urn:uuid:");
        @memcpy(serialNumber[9..], urn[0..]);

        var bom: @This() = .{
            .serialNumber = serialNumber,
        };
        errdefer bom.deinit(allocator);

        bom.version = 1;

        return bom;
    }

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        self.metadata.deinit(allocator);

        if (self.components) |comps| {
            for (comps) |comp| comp.deinit(allocator);
            allocator.free(comps);
        }
        self.components = null;

        if (self.dependencies) |dependencies| {
            for (dependencies) |dependency| dependency.deinit(allocator);
            allocator.free(dependencies);
        }
        self.dependencies = null;
    }

    pub fn toJson(self: *@This(), allocator: Allocator) ![]u8 {
        return try std.json.stringifyAlloc(
            allocator,
            self,
            .{
                .emit_strings_as_arrays = false,
                .whitespace = .indent_2,
                .emit_null_optional_fields = false,
            },
        );
    }

    pub const Options = struct {
        /// The type of the component that the SBOM describes.
        type: Component.Type = .application,
        /// The main components name. Usually the name specified in build.zig.zon.
        name: []const u8,
        /// A group name like a company name, project name, or domain name.
        group: []const u8 = "thesugar.de",
        /// The version numer. Usually the version number set in build.zig.zon.
        version: ?[]const u8 = null,
        /// A description of the main component.
        description: ?[]const u8 = null,
        /// A list of authors of the main component.
        authors: ?[]const Component.Author = null,
        allocator: Allocator,
    };

    pub fn addDependency(
        self: *@This(),
        dependency: Dependency,
        allocator: Allocator,
    ) !void {
        var dependencies = if (self.dependencies) |deps| std.ArrayList(Dependency).fromOwnedSlice(allocator, deps) else std.ArrayList(Dependency).init(allocator);

        for (dependencies.items) |dep| {
            // We don't add the same dependency twice
            if (std.mem.eql(u8, dep.ref, dependency.ref)) {
                self.dependencies = try dependencies.toOwnedSlice();
                return;
            }
        }

        try dependencies.append(dependency);

        self.dependencies = try dependencies.toOwnedSlice();
    }

    pub fn addComponent(
        self: *@This(),
        comp: Component,
        allocator: Allocator,
    ) !void {
        var components = if (self.components) |comps| std.ArrayList(Component).fromOwnedSlice(allocator, comps) else std.ArrayList(Component).init(allocator);

        try components.append(comp);

        self.components = try components.toOwnedSlice();
    }

    pub fn getComponentByRef(
        self: *const @This(),
        ref: []const u8,
    ) ?*Component {
        if (self.components == null) return null;

        for (self.components.?) |*comp| {
            if (comp.@"bom-ref") |ref2| {
                if (std.mem.eql(u8, ref2, ref)) return comp;
            }
        }

        return null;
    }
};
