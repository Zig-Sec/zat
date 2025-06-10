const std_zat_ = @import("std");

pub const zat = struct {
    pub const Components = struct {
        components: []Component,

        pub const Component = struct {
            name: []const u8,
            version: ?[]const u8,
            imports: []Component,
            type: Type,
            root_source_file: ?[]const u8 = null,

            pub const Type = enum {
                module,
                library,
                executable,
            };

            pub fn fromCompile(
                allocator: std_zat_.mem.Allocator,
                cs: *const std_zat_.Build.Step.Compile,
            ) !Component {
                var imports = std_zat_.ArrayList(Component).init(allocator);

                var iter = cs.root_module.import_table.iterator();
                while (iter.next()) |kv| {
                    try imports.append(.{
                        .name = try allocator.dupe(u8, kv.key_ptr.*),
                        .version = null, // modules don't have a version right now...
                        .imports = &.{},
                        .type = .module,
                        .root_source_file = if (kv.value_ptr.*.root_source_file) |rsf| try allocator.dupe(u8, rsf.getDisplayName()) else null,
                    });
                }

                return .{
                    .name = try allocator.dupe(u8, cs.out_filename),
                    .version = if (cs.version) |v| try std_zat_.fmt.allocPrint(
                        allocator,
                        "{d}.{d}.{d}{s}{s}{s}{s}",
                        .{
                            v.major,
                            v.minor,
                            v.patch,
                            if (v.pre) |_| "-" else "",
                            if (v.pre) |pre| pre else "",
                            if (v.build) |_| "+" else "",
                            if (v.build) |b| b else "",
                        },
                    ) else null,
                    .type = switch (cs.kind) {
                        .exe => .executable,
                        else => .library,
                    },
                    .imports = try imports.toOwnedSlice(),
                };
            }

            pub fn fromModule(
                name: []const u8,
                allocator: std_zat_.mem.Allocator,
                mod: *const std_zat_.Build.Module,
            ) !Component {
                var imports = std_zat_.ArrayList(Component).init(allocator);

                var iter = mod.import_table.iterator();
                while (iter.next()) |kv| {
                    try imports.append(.{
                        .name = try allocator.dupe(u8, kv.key_ptr.*),
                        .version = null, // modules don't have a version right now...
                        .imports = &.{},
                        .type = .module,
                    });
                }

                return .{
                    .name = try allocator.dupe(u8, name),
                    .version = null,
                    .type = .module,
                    .imports = try imports.toOwnedSlice(),
                    .root_source_file = if (mod.root_source_file) |rsf| try allocator.dupe(u8, rsf.getDisplayName()) else null,
                };
            }
        };
    };

    pub const Build = struct {
        build: *std_zat_.Build,
        modules: std_zat_.StringArrayHashMap(*std_zat_.Build.Module),

        compiles: std_zat_.ArrayList(*std_zat_.Build.Step.Compile),

        args: ?[]const []const u8 = null,

        pub fn new(b: *std_zat_.Build) @This() {
            return .{
                .build = b,
                .modules = b.modules,
                .compiles = std_zat_.ArrayList(*std_zat_.Build.Step.Compile).init(b.allocator),
            };
        }

        pub fn standardTargetOptions(b: *Build, args: std_zat_.Build.StandardTargetOptionsArgs) std_zat_.Build.ResolvedTarget {
            return b.build.standardTargetOptions(args);
        }

        pub fn standardOptimizeOption(b: *Build, options: std_zat_.Build.StandardOptimizeOptionOptions) std_zat_.builtin.OptimizeMode {
            return b.build.standardOptimizeOption(options);
        }

        pub fn dependency(b: *Build, name: []const u8, args: anytype) *std_zat_.Build.Dependency {
            return b.build.dependency(name, args);
        }

        pub fn createModule(b: *Build, options: std_zat_.Build.Module.CreateOptions) *std_zat_.Build.Module {
            const mod = b.build.createModule(options);

            return mod;
        }

        pub fn addModule(b: *Build, name: []const u8, options: std_zat_.Build.Module.CreateOptions) *std_zat_.Build.Module {
            const mod = b.build.addModule(name, options);

            return mod;
        }

        pub fn path(b: *Build, sub_path: []const u8) std_zat_.Build.LazyPath {
            return b.build.path(sub_path);
        }

        pub fn addExecutable(b: *Build, options: std_zat_.Build.ExecutableOptions) *std_zat_.Build.Step.Compile {
            const comp = b.build.addExecutable(options);

            b.compiles.append(comp) catch |e| {
                std_zat_.process.fatal("unable to append executable ({any})", .{e});
            };

            return comp;
        }

        pub fn addLibrary(b: *Build, options: std_zat_.Build.LibraryOptions) *std_zat_.Build.Step.Compile {
            const comp = b.build.addLibrary(options);

            b.compiles.append(comp) catch |e| {
                std_zat_.process.fatal("unable to append library ({any})", .{e});
            };

            return comp;
        }

        pub fn installArtifact(b: *Build, artifact: *std_zat_.Build.Step.Compile) void {
            return b.build.installArtifact(artifact);
        }

        pub fn addRunArtifact(b: *Build, exe: *std_zat_.Build.Step.Compile) *std_zat_.Build.Step.Run {
            return b.build.addRunArtifact(exe);
        }

        pub fn getInstallStep(b: *Build) *std_zat_.Build.Step {
            return b.build.getInstallStep();
        }

        pub fn step(b: *Build, name: []const u8, description: []const u8) *std_zat_.Build.Step {
            return b.build.step(name, description);
        }

        pub fn addTest(b: *Build, options: std_zat_.Build.TestOptions) *std_zat_.Build.Step.Compile {
            return b.build.addTest(options);
        }

        pub fn dupe(b: *Build, bytes: []const u8) []u8 {
            return b.build.dupe(bytes);
        }

        pub fn addInstallArtifact(b: *Build, artifact: *std_zat_.Build.Step.Compile, options: std_zat_.Build.Step.InstallArtifact.Options) *std_zat_.Build.Step.InstallArtifact {
            const artifact_ = b.build.addInstallArtifact(artifact, options);

            return artifact_;
        }
    };
};
