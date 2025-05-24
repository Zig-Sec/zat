//! This code is derived from the work of `tenorush` ([meduza](https://github.com/arrufat/meduza/blob/main/src/meduza.zig))

const std = @import("std");
const Allocator = std.mem.Allocator;

const MAX_NUM_ARGS: usize = 1 << 4;
const MAX_FILE_SIZE: u32 = 1 << 22;
const MAX_NUM_DECLS: usize = 1 << 8;
const MAX_NUM_FUNCS: usize = 1 << 8;
const MAX_NUM_TYPES: usize = 1 << 8;
const MAX_FILE_PATH_LEN: u16 = 1 << 6;

pub const tree = struct {
    pub const Container = struct {
        name: []const u8,
        container: std.ArrayList(*Container),
        functions: std.ArrayList(*Function),
        parent: ?*Container = null,

        pub fn new(allocator: Allocator, name: []const u8, parent: ?*Container) !*Container {
            var c = try allocator.create(Container);
            c.name = try allocator.dupe(u8, name);
            c.container = std.ArrayList(*Container).init(allocator);
            c.functions = std.ArrayList(*Function).init(allocator);
            c.parent = parent;
            return c;
        }
    };

    pub const Function = struct {
        name: []const u8,
        args: []const []const u8,
        is_pub: bool,
        parent: *Container,
    };
};

/// Type declaration
const Type = struct {
    start: std.zig.Ast.ByteOffset,
    end: std.zig.Ast.ByteOffset,

    const Tag = enum {
        /// Struct
        str,
        /// Opaque
        opa,
        /// Union
        uni,
        /// Error
        err,
        /// Enum
        enu,
    };
};

/// Function declaration
const Func = struct {
    args: std.BoundedArray(struct { start: std.zig.Ast.ByteOffset, end: std.zig.Ast.ByteOffset }, MAX_NUM_ARGS),
    rt_start: std.zig.Ast.ByteOffset,
    rt_end: std.zig.Ast.ByteOffset,
    is_pub: bool,
};

/// Simple declaration
const Decl = struct {
    start: std.zig.Ast.ByteOffset,
    end: std.zig.Ast.ByteOffset,
    tag: Tag,

    const Tag = enum {
        /// Container field
        fld,
        /// Test function
        tst,
    };
};

//pub fn detectModulesFromBuildZig(
//    allocator: Allocator,
//    local_src_dir: std.fs.Dir,
//) !void {
//    var f = try local_src_dir.openFile("build.zig", .{});
//    defer f.close();
//
//    var src_buf: [MAX_FILE_SIZE]u8 = undefined;
//    const l = try f.readAll(&src_buf);
//    src_buf[l] = 0;
//    const src = src_buf[0..l];
//
//    const ast = try std.zig.Ast.parse(allocator, @ptrCast(src), .zig);
//    const main_tokens = ast.nodes.items(.main_token);
//    const node_data = ast.nodes.items(.data);
//    const node_tags = ast.nodes.items(.tag);
//    const token_tags = ast.tokens.items(.tag);
//    const starts = ast.tokens.items(.start);
//
//    for (node_tags, 0..) |node_tag, i| {
//        //std.debug.print("{any}\n", .{node_tag});
//    }
//
//}

pub const ModuleChecker = struct {
    module_name: []const u8,
    used: bool = false,
    containers: std.ArrayList(Cont),
    allocator: Allocator,

    pub const Cont = struct {
        name: []const u8,
        mod_identifiers: std.ArrayList([]const u8),
        identifier_mappings: std.StringHashMap([]const u8),
        allocator: Allocator,

        pub fn deinit(self: *const @This()) void {
            self.allocator.free(self.name);
            for (self.mod_identifiers.items) |ident| {
                self.allocator.free(ident);
            }
            self.mod_identifiers.deinit();
        }

        pub fn addIdentifier(self: *@This(), ident: []const u8) !void {
            for (self.mod_identifiers.items) |ident_| {
                if (std.mem.eql(u8, ident_, ident)) return;
            }

            try self.mod_identifiers.append(try self.allocator.dupe(u8, ident));
        }

        pub fn identifierExists(self: *@This(), ident: []const u8) bool {
            for (self.mod_identifiers.items) |ident_| {
                if (std.mem.eql(u8, ident_, ident)) return true;
            }
            return false;
        }

        pub fn addMapping(self: *@This(), lhs: []const u8, rhs: []const u8) !void {
            const result = try self.identifier_mappings.getOrPut(lhs);

            if (!result.found_existing) {
                result.value_ptr.* = try self.allocator.dupe(u8, rhs);
            }
        }
    };

    pub fn getContainer(self: *const @This(), name: []const u8) ?*Cont {
        for (self.containers.items) |*cont| {
            if (std.mem.eql(u8, cont.name, name)) return cont;
        }
        return null;
    }

    pub fn addContainer(self: *@This(), name: []const u8) !*Cont {
        for (self.containers.items) |*cont| {
            if (std.mem.eql(u8, cont.name, name)) return cont;
        }

        try self.containers.append(.{
            .name = try self.allocator.dupe(u8, name),
            .mod_identifiers = std.ArrayList([]const u8).init(self.allocator),
            .identifier_mappings = std.StringHashMap([]const u8).init(self.allocator),
            .allocator = self.allocator,
        });

        return &self.containers.items[self.containers.items.len - 1];
    }

    pub fn deinit(self: *const @This()) void {
        self.allocator.free(self.module_name);
        for (self.containers.items) |cont| {
            cont.deinit();
        }
        self.containers.deinit();
    }
};

pub const Modules = struct {
    mods: std.ArrayList(Module),
    allocator: Allocator,

    pub const Module = struct {
        name: []const u8,
        containers: std.ArrayList(Cont),
        allocator: Allocator,

        pub const Cont = struct {
            name: []const u8,
            /// Identifiers the module is directly bound to
            mod_identifiers: std.ArrayList([]const u8),
            /// Accesses to the module.
            ///
            /// TODO: this currently tracks only direct accesses, i.e. where
            /// an module identifier is used directly (first identifier in an
            /// access chain). Cases where a container, function, etc. exposed
            /// by the module is bound to an intermediate variable are not supported
            /// right now.
            accesses: std.ArrayList([]const u8),
            allocator: Allocator,

            pub fn deinit(self: *const @This()) void {
                self.allocator.free(self.name);
                for (self.mod_identifiers.items) |ident| {
                    self.allocator.free(ident);
                }
                self.mod_identifiers.deinit();
                for (self.accesses.items) |ident| {
                    self.allocator.free(ident);
                }
                self.accesses.deinit();
            }

            pub fn addIdentifier(self: *@This(), ident: []const u8) !void {
                for (self.mod_identifiers.items) |ident_| {
                    if (std.mem.eql(u8, ident_, ident)) return;
                }

                try self.mod_identifiers.append(try self.allocator.dupe(u8, ident));
            }

            pub fn identifierExists(self: *@This(), ident: []const u8) bool {
                for (self.mod_identifiers.items) |ident_| {
                    if (std.mem.eql(u8, ident_, ident)) return true;
                }
                return false;
            }

            pub fn addAccess(self: *@This(), str: []const u8) !void {
                for (self.accesses.items) |str_| {
                    if (std.mem.eql(u8, str_, str)) return;
                }

                try self.accesses.append(try self.allocator.dupe(u8, str));
            }
        };

        pub fn getContainer(self: *const @This(), name: []const u8) ?*Cont {
            for (self.containers.items) |*cont| {
                if (std.mem.eql(u8, cont.name, name)) return cont;
            }
            return null;
        }

        pub fn addContainer(self: *@This(), name: []const u8) !*Cont {
            for (self.containers.items) |*cont| {
                if (std.mem.eql(u8, cont.name, name)) return cont;
            }

            try self.containers.append(.{
                .name = try self.allocator.dupe(u8, name),
                .mod_identifiers = std.ArrayList([]const u8).init(self.allocator),
                .accesses = std.ArrayList([]const u8).init(self.allocator),
                .allocator = self.allocator,
            });

            return &self.containers.items[self.containers.items.len - 1];
        }

        pub fn deinit(self: *const @This()) void {
            self.allocator.free(self.name);
            for (self.containers.items) |cont| {
                cont.deinit();
            }
            self.containers.deinit();
        }
    };

    pub fn addModule(self: *@This(), name: []const u8) !*Module {
        for (self.mods.items) |*mod| {
            if (std.mem.eql(u8, mod.name, name)) return mod;
        }

        try self.mods.append(.{
            .name = try self.allocator.dupe(u8, name),
            .containers = std.ArrayList(Module.Cont).init(self.allocator),
            .allocator = self.allocator,
        });

        return &self.mods.items[self.mods.items.len - 1];
    }

    pub fn deinit(self: *const @This()) void {
        for (self.mods.items) |mod| {
            mod.deinit();
        }
        self.mods.deinit();
    }
};

pub const VisitedContainers = struct {
    containers: std.ArrayList(Container),
    allocator: Allocator,

    pub const Container = struct {
        path: []const u8,
        visited: bool = false,

        pub fn deinit(self: *const @This(), allocator: Allocator) void {
            allocator.free(self.path);
        }
    };

    pub fn new(allocator: Allocator) @This() {
        return .{
            .containers = std.ArrayList(Container).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *const @This()) void {
        for (self.containers.items) |cont| {
            cont.deinit(self.allocator);
        }
    }

    pub fn addFile(self: *@This(), p: []const u8) !void {
        for (self.containers.items) |cont| {
            if (std.mem.eql(u8, cont.path, p)) return;
        }

        try self.containers.append(.{
            .path = try self.allocator.dupe(u8, p),
        });
    }

    /// Return the next unvisited container.
    ///
    /// This will set the status of the returned container to
    /// visited, i.e., the caller is expected to actually visit
    /// the container right after calling this method.
    pub fn getNextUnvisited(self: *@This()) ?*Container {
        for (self.containers.items) |*cont| {
            if (!cont.visited) {
                cont.visited = true;
                return cont;
            }
        }

        return null;
    }
};

/// Check if a module uses one or more of the given `modules`.
///
/// - `local_src_dir`: The package root.
/// - `file_path`: Path to the root file from the package root. A package can have multiple root files (usually `src/root.zig` and/or `src/main.zig`), i.e. this function should be called multiple times for every (suspected) root file.
/// - `modules`: A list of modules to check. The `.used` field is set to true if a module with the provided name is found.
pub fn getUsedModules(
    allocator: Allocator,
    local_src_dir: std.fs.Dir,
    file_path: []const u8,
) !Modules {
    var mods = Modules{
        .mods = std.ArrayList(Modules.Module).init(allocator),
        .allocator = allocator,
    };
    errdefer mods.deinit();

    var containers = VisitedContainers.new(allocator);
    defer containers.deinit();

    var current_path = try local_src_dir.realpathAlloc(allocator, file_path);
    var current_base = std.fs.path.dirname(current_path).?;
    var f = try local_src_dir.openFile(file_path, .{});

    while (true) {
        var src_buf: [MAX_FILE_SIZE]u8 = undefined;
        const l = try f.readAll(&src_buf);
        src_buf[l] = 0;
        const src = src_buf[0..l];

        const ast = try std.zig.Ast.parse(allocator, @ptrCast(src), .zig);
        const main_tokens = ast.nodes.items(.main_token);
        const node_data = ast.nodes.items(.data);
        const node_tags = ast.nodes.items(.tag);
        const token_tags = ast.tokens.items(.tag);
        const starts = ast.tokens.items(.start);

        _ = token_tags;

        for (node_tags, 0..) |node_tag, i| {
            //std.debug.print("{any}\n", .{node_tag});

            switch (node_tag) {
                .identifier => {
                    const start = starts[main_tokens[i]];
                    const ident = getIdentSlice(src[start..]) catch continue;

                    for (mods.mods.items) |*mod| {
                        if (mod.getContainer(file_path)) |cont| {
                            if (cont.identifierExists(ident)) {
                                var access = std.ArrayList(u8).init(allocator);
                                defer access.deinit();

                                try access.appendSlice(ident);

                                for (node_tags[i + 1 ..], i + 1..) |tag, j| {
                                    switch (tag) {
                                        .field_access,
                                        => {
                                            const ident2_start = starts[node_data[j].rhs];
                                            const ident2 = getIdentSlice(src[ident2_start..]) catch continue;
                                            try access.writer().print(".{s}", .{ident2});
                                        },
                                        //.call_one,
                                        //.call_one_comma,
                                        //.async_call_one,
                                        //.async_call_one_comma,
                                        //.call,
                                        //.call_comma,
                                        //.async_call,
                                        //.async_call_comma,
                                        //=> {
                                        //    std.debug.print("()", .{});
                                        //},
                                        else => break,
                                    }
                                }

                                // TODO: this is currently only used for debugging purposes.
                                // In the future, we will use this variable to track
                                // access to modules more precisely.
                                var var_name: ?[]const u8 = null;

                                switch (node_tags[i - 1]) {
                                    .global_var_decl,
                                    .local_var_decl,
                                    .simple_var_decl,
                                    => {
                                        var var_name_start = starts[main_tokens[i - 1]];
                                        while (var_name_start < src.len and src[var_name_start] != ' ') var_name_start += 1;
                                        var_name_start += 1;
                                        var_name = try getIdentSlice(src[var_name_start..]);
                                    },
                                    else => {},
                                }

                                //std.debug.print("{s} -> {s}\n", .{ access.items, if (var_name) |vn| vn else "_" });

                                try cont.addAccess(access.items);
                            }
                        }
                    }
                },
                .builtin_call_two => {
                    const builtin_func_name_start = starts[main_tokens[i]];

                    // Check if the function is @import
                    if (builtin_func_name_start + 7 < src.len and std.mem.eql(u8, src[builtin_func_name_start .. builtin_func_name_start + 7], "@import")) {
                        // Extract the name of imported module or container and bind it
                        // to import_name.
                        var import_string_start = starts[main_tokens[node_data[i].lhs]];
                        if (src[import_string_start] == '"') import_string_start += 1;
                        var import_string_end: usize = import_string_start + 1;
                        while (import_string_end < src.len and src[import_string_end] != '"' and src[import_string_end] != ')') import_string_end += 1;
                        const import_name = src[import_string_start..import_string_end];
                        // Try to get the name of the variable the import is bound to.
                        var var_name: ?[]const u8 = null;
                        if (i >= 2) {
                            switch (node_tags[i - 2]) {
                                .global_var_decl,
                                .local_var_decl,
                                .simple_var_decl,
                                => {
                                    var var_name_start = starts[main_tokens[i - 2]];
                                    while (var_name_start < src.len and src[var_name_start] != ' ') var_name_start += 1;
                                    var_name_start += 1;
                                    var_name = try getIdentSlice(src[var_name_start..]);
                                },
                                else => {},
                            }
                        }

                        // We filter for modules
                        if (!std.mem.endsWith(u8, import_name, ".zig") and !std.mem.endsWith(u8, import_name, ".zon")) {
                            const mod = try mods.addModule(import_name);

                            const cont = try mod.addContainer(current_path);
                            if (var_name) |vname| {
                                try cont.addIdentifier(vname);
                            }
                        } else if (std.mem.endsWith(u8, import_name, ".zig")) {
                            const p = try std.fs.path.resolve(allocator, &.{ current_base, import_name });
                            defer allocator.free(p);

                            try containers.addFile(p);
                        }

                        //std.debug.print("{s} {s}\n", .{ if (var_name) |vn| vn else "_", import_name });
                    }
                },
                else => {}, // skip
            }
        }

        //for (containers.containers.items) |cont| {
        //    if (!cont.visited) {
        //        std.debug.print("{s}, {any}\n", .{ cont.path, cont.visited });
        //    }
        //}
        //std.debug.print("\n", .{});

        if (containers.getNextUnvisited()) |unvisited| {
            allocator.free(current_path);
            current_path = try allocator.dupe(u8, unvisited.path);

            current_base = std.fs.path.dirname(current_path).?;

            f.close();
            f = try std.fs.openFileAbsolute(current_path, .{});
        } else {
            break;
        }
    }

    return mods;
}

/// Check if a module uses one or more of the given `modules`.
///
/// - `local_src_dir`: The package root.
/// - `file_path`: Path to the root file from the package root. A package can have multiple root files (usually `src/root.zig` and/or `src/main.zig`), i.e. this function should be called multiple times for every (suspected) root file.
/// - `modules`: A list of modules to check. The `.used` field is set to true if a module with the provided name is found.
pub fn usesModule(
    allocator: Allocator,
    local_src_dir: std.fs.Dir,
    file_path: []const u8,
    modules: []ModuleChecker,
) !void {
    var f = try local_src_dir.openFile(file_path, .{});

    while (true) {
        var src_buf: [MAX_FILE_SIZE]u8 = undefined;
        const l = try f.readAll(&src_buf);
        src_buf[l] = 0;
        const src = src_buf[0..l];

        const ast = try std.zig.Ast.parse(allocator, @ptrCast(src), .zig);
        const main_tokens = ast.nodes.items(.main_token);
        const node_data = ast.nodes.items(.data);
        const node_tags = ast.nodes.items(.tag);
        const token_tags = ast.tokens.items(.tag);
        const starts = ast.tokens.items(.start);

        _ = token_tags;

        for (node_tags, 0..) |node_tag, i| {
            //std.debug.print("{any}\n", .{node_tag});

            switch (node_tag) {
                .identifier => {
                    const start = starts[main_tokens[i]];
                    const ident = getIdentSlice(src[start..]) catch continue;
                    //std.debug.print("{s}\n", .{ident});

                    for (modules) |*mod| {
                        if (mod.getContainer(file_path)) |cont| {
                            if (cont.identifierExists(ident)) {}
                        }
                    }
                },
                .builtin_call_two => {
                    const builtin_func_name_start = starts[main_tokens[i]];

                    // Check if the function is @import
                    if (builtin_func_name_start + 7 < src.len and std.mem.eql(u8, src[builtin_func_name_start .. builtin_func_name_start + 7], "@import")) {
                        // Extract the name of imported module or container and bind it
                        // to import_name.
                        var import_string_start = starts[main_tokens[node_data[i].lhs]];
                        if (src[import_string_start] == '"') import_string_start += 1;
                        var import_string_end: usize = import_string_start + 1;
                        while (import_string_end < src.len and src[import_string_end] != '"' and src[import_string_end] != ')') import_string_end += 1;
                        const import_name = src[import_string_start..import_string_end];
                        // Try to get the name of the variable the import is bound to.
                        var var_name: ?[]const u8 = null;
                        if (i >= 2) {
                            switch (node_tags[i - 2]) {
                                .global_var_decl,
                                .local_var_decl,
                                .simple_var_decl,
                                => {
                                    var var_name_start = starts[main_tokens[i - 2]];
                                    while (var_name_start < src.len and src[var_name_start] != ' ') var_name_start += 1;
                                    var_name_start += 1;
                                    var_name = try getIdentSlice(src[var_name_start..]);
                                },
                                else => {},
                            }
                        }

                        for (modules) |*mod| {
                            // Check if the import is a module we're looking for.
                            if (std.mem.eql(u8, mod.module_name, import_name)) {
                                mod.used = true;

                                const cont = try mod.addContainer(file_path);
                                if (var_name) |vname| {
                                    try cont.addIdentifier(vname);
                                }

                                for (cont.mod_identifiers.items) |ident| {
                                    std.debug.print("{s}, ", .{ident});
                                }
                                std.debug.print("\n", .{});
                            }
                        }

                        std.debug.print("{s} {s}\n", .{ if (var_name) |vn| vn else "_", import_name });
                    }
                },
                else => {}, // skip
            }
        }

        break;
    }
}

pub fn generate(
    tree_: *tree.Container,
    allocator: Allocator,
    local_src_dir: std.fs.Dir,
    file_path: []const u8,
) !void {
    _ = tree_;

    var f = try local_src_dir.openFile(file_path, .{});

    while (true) {
        var src_buf: [MAX_FILE_SIZE]u8 = undefined;
        const l = try f.readAll(&src_buf);
        src_buf[l] = 0;
        const src = src_buf[0..l];

        const ast = try std.zig.Ast.parse(allocator, @ptrCast(src), .zig);
        const main_tokens = ast.nodes.items(.main_token);
        const node_data = ast.nodes.items(.data);
        const node_tags = ast.nodes.items(.tag);
        const token_tags = ast.tokens.items(.tag);
        const starts = ast.tokens.items(.start);

        for (node_tags, 0..) |node_tag, i| {
            std.debug.print("{any}\n", .{node_tag});

            switch (node_tag) {
                .fn_proto_simple, .fn_proto_multi, .fn_proto_one, .fn_proto => {
                    const start = starts[main_tokens[i] + 1];

                    // Parse only function declarations
                    switch (src[start]) {
                        // Skip function types
                        '(' => continue,
                        // Skip extern functions
                        else => switch (token_tags[main_tokens[i] - 1]) {
                            .keyword_extern, .string_literal => continue,
                            else => {},
                        },
                    }

                    var end_token_idx: std.zig.Ast.TokenIndex = undefined;
                    var rt_end: std.zig.Ast.ByteOffset = undefined;

                    // Find return type
                    for (node_tags[i + 1 ..], i + 1..) |tag, j| {
                        if (tag == .fn_decl) {
                            end_token_idx = main_tokens[node_data[j].rhs];
                            rt_end = starts[end_token_idx] - 1;
                            break;
                        }
                    }
                },
                .global_var_decl,
                .local_var_decl,
                .simple_var_decl,
                => {
                    // Detect @import's
                    //
                    // Those are interesting, as they determine which files to parse next
                    // and also tell us which external moduels are imported.
                    if (node_tags[i + 1] == .string_literal and node_tags[i + 2] == .builtin_call_two) {
                        const bc2_idx = i + 2;

                        const builtin_func_name_start = starts[main_tokens[bc2_idx]];
                        if (builtin_func_name_start + 7 < src.len and std.mem.eql(u8, src[builtin_func_name_start .. builtin_func_name_start + 7], "@import")) {
                            const import_string_start = starts[main_tokens[node_data[bc2_idx].lhs]] + 1;
                            var import_string_end: usize = import_string_start + 1;
                            while (import_string_end < src.len and src[import_string_end] != '"') import_string_end += 1;
                            const import_string = src[import_string_start..import_string_end];

                            var var_name_start = starts[main_tokens[i]];
                            while (var_name_start < src.len and src[var_name_start] != ' ') var_name_start += 1;
                            var_name_start += 1;
                            var var_name_end = var_name_start + 1;
                            while (var_name_end < src.len and src[var_name_end] != ' ') var_name_end += 1;
                            const var_string = src[var_name_start..var_name_end];
                            std.debug.print("{s} {s}\n", .{ var_string, import_string });
                        }
                    }
                },
                else => {}, // skip
            }
        }

        break;
    }
}

pub fn getIdentSlice(s: []const u8) ![]const u8 {
    var escaped = false;
    var start: usize = 0;

    if (s[start] == '@') {
        start += 2;
        escaped = true;
    }

    if (escaped) {
        var end: usize = start + 1;
        while (end < s.len and s[end] != '"') end += 1;
        return s[start..end];
    } else {
        var end: usize = start;
        while (end < s.len) {
            switch (s[end]) {
                'a'...'z', 'A'...'Z', '0'...'9', '_' => end += 1,
                else => break,
            }
        }
        return s[start..end];
    }
}
