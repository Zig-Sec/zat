const std_zat_ = @import("std");

pub const zat = struct {
    pub const Components = struct {
        components: []Component,

        pub const Component = struct {
            name: []const u8,
            version: ?[]const u8 = null,
            imports: []Component,
            type: Type,
            root_source_file: ?[]const u8 = null,

            pub const Type = enum {
                module,
                library,
                executable,
            };

            pub fn deinit(self: *const @This(), allocator: std_zat_.mem.Allocator) void {
                allocator.free(self.name);
                if (self.version) |v| allocator.free(v);
                for (self.imports) |imp| imp.deinit(allocator);
                if (self.root_source_file) |rsf| allocator.free(rsf);
            }

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
                    .root_source_file = if (cs.root_module.root_source_file) |rsf| try allocator.dupe(u8, rsf.getDisplayName()) else null,
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

        pub fn fromBuild(b: *const std_zat_.Build) !@This() {
            var components = std_zat_.ArrayList(Component).init(b.allocator);

            var mod_iter = b.modules.iterator();
            while (mod_iter.next()) |kv| {
                try components.append(try Component.fromModule(kv.key_ptr.*, b.allocator, kv.value_ptr.*));
            }

            var step_iter = b.top_level_steps.iterator();
            while (step_iter.next()) |kv| {
                try findCompiles(&components, &kv.value_ptr.*.step, b.allocator);
            }

            return .{
                .components = try components.toOwnedSlice(),
            };
        }

        fn findCompiles(c: *std_zat_.ArrayList(Component), s: *std_zat_.Build.Step, a: std_zat_.mem.Allocator) !void {
            switch (s.id) {
                .compile => {
                    const cs = s.cast(std_zat_.Build.Step.Compile).?;
                    try addIfNotPresent(c, try Component.fromCompile(a, cs));
                },
                else => {},
            }

            for (s.dependencies.items) |dep| {
                try findCompiles(c, dep, a);
            }
        }

        fn addIfNotPresent(c: *std_zat_.ArrayList(Component), rhs: Component) !void {
            for (c.items) |lhs| {
                // Check if rhs already exists
                if (std_zat_.mem.eql(u8, lhs.name, rhs.name) and lhs.type == rhs.type) return;
            }

            try c.append(rhs);
        }

        pub fn deinit(self: *const @This(), allocator: std_zat_.mem.Allocator) void {
            for (self.components) |comp| comp.deinit(allocator);
            allocator.free(self.components);
        }
    };
};
