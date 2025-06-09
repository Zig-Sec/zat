const std = @import("std");
const Allocator = std.mem.Allocator;

const MAX_NUM_ARGS: usize = 1 << 4;
const MAX_FILE_SIZE: u32 = 1 << 22;
const MAX_NUM_DECLS: usize = 1 << 8;
const MAX_NUM_FUNCS: usize = 1 << 8;
const MAX_NUM_TYPES: usize = 1 << 8;
const MAX_FILE_PATH_LEN: u16 = 1 << 6;

const MAX_SEARCH_LEN = 3;

pub const Component = struct {
    name: []const u8,
    root_source_file: []const u8,
    modules: std.ArrayList([]const u8),
    allocator: Allocator,
};

pub const State = struct {
    dependencies: std.StringHashMap([]const u8),
    allocator: Allocator,

    pub fn new(allocator: Allocator) @This() {
        return .{
            .dependencies = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        var miter = self.dependencies.iterator();
        while (miter.next()) |kv| {
            self.allocator.free(kv.key_ptr.*);
            self.allocator.free(kv.value_ptr.*);
        }
        self.dependencies.deinit();
    }
};

pub fn read(
    allocator: Allocator,
    package_root_dir: std.fs.Dir,
) ![]const Component {
    var components = std.ArrayList(Component).init(allocator);
    errdefer {
        components.deinit();
    }

    var state = State.new(allocator);
    defer state.deinit();

    var f = try package_root_dir.openFile("build.zig", .{});
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

    std.debug.print("Parse ZON file\n", .{});
    outer: for (node_tags, 0..) |node_tag, i| {
        std.debug.print("{any}\n", .{node_tag});

        switch (node_tag) {
            .field_access => {
                const ident_start = starts[node_data[i].rhs];
                const ident = getIdentSlice(src[ident_start..]) catch continue;
                //std.debug.print("{s}\n", .{ident});

                if (std.mem.eql(u8, "dependency", ident)) { // find dependencies
                    if (node_tags[i + 1] != .string_literal) continue :outer;
                    const sl = getString(src[starts[main_tokens[i + 1]]..]) catch {
                        continue :outer;
                    };

                    const var_name = findVar(ast, src, i, allocator) catch continue :outer;

                    try state.dependencies.put(
                        try allocator.dupe(u8, var_name),
                        try allocator.dupe(u8, sl),
                    );
                    std.debug.print("{s} -> {s}\n", .{ var_name, sl });
                } else if (std.mem.eql(u8, "module", ident)) {
                    if (node_tags[i - 1] != .identifier) continue :outer;
                    if (node_tags[i + 1] != .string_literal) continue :outer;

                    const package_ident = getIdentSlice(src[starts[main_tokens[i - 1]]..]) catch continue;
                    const mod_name = getString(src[starts[main_tokens[i + 1]]..]) catch {
                        continue :outer;
                    };

                    std.debug.print("{s}.{s}\n", .{ package_ident, mod_name });

                    // TODO: cover cases where the module is assigned to a variable
                    if (node_tags[i - 2] == .string_literal and node_tags[i - 3] == .field_access) exit_case: { // e.g. exe.root_module.addImport("keylib", keylib_dep.module("keylib"));

                        const fname = getIdentSlice(src[starts[node_data[i - 3].rhs]..]) catch break :exit_case;
                        if (!std.mem.eql(u8, "addImport", fname)) break :exit_case;
                        const actual_mod_name = getString(src[starts[main_tokens[i - 2]]..]) catch break :exit_case;

                        std.debug.print("  as: {s}\n", .{actual_mod_name});

                        const comp_ident = inner: for (1..MAX_SEARCH_LEN) |j| {
                            const k = i - (3 + j);

                            switch (node_tags[k]) {
                                .identifier => {
                                    break :inner getIdentSlice(src[starts[main_tokens[k]]..]) catch break :exit_case;
                                },
                                .field_access => {},
                                else => break :exit_case,
                            }
                        } else break :exit_case;

                        std.debug.print("  for: {s}\n", .{comp_ident});
                    }
                    // TODO: store this information
                } else if (std.mem.eql(u8, "addExecutable", ident)) {
                    const var_name = findVar(ast, src, i, allocator) catch continue :outer;

                    std.debug.print("{s} := addExecutable\n", .{var_name});

                    const is = InitStruct.parse(src, ident_start, allocator) catch continue;
                    _ = is;
                }
            },
            .call => {
                //const fname_start = starts[main_tokens[i]];
                //std.debug.print("{s}\n", .{src[fname_start - 10 .. fname_start]});
            },
            else => {},
        }
    }

    return try components.toOwnedSlice();
}

pub fn getString(s: []const u8) ![]const u8 {
    var start: usize = 0;
    while (start < s.len and s[start] != '"') start += 1;
    if (s[start] != '"') return error.UnexpectedStartByte;
    start += 1;

    var end: usize = start;
    while (end < s.len and s[end] != '"') end += 1;
    if (s[end] != '"') return error.UnexpectedEndByte;

    return s[start..end];
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

pub fn findVar(ast: std.zig.Ast, src: []const u8, i: usize, allocator: Allocator) ![]const u8 {
    const node_tags = ast.nodes.items(.tag);
    const starts = ast.tokens.items(.start);
    const main_tokens = ast.nodes.items(.main_token);

    return inner: for (1..MAX_SEARCH_LEN) |j| {
        switch (node_tags[i - j]) {
            .local_var_decl,
            .simple_var_decl,
            => {
                var var_name_start = starts[main_tokens[i - j]];
                while (var_name_start < src.len and src[var_name_start] != ' ') var_name_start += 1;
                var_name_start += 1;
                break :inner try allocator.dupe(u8, try getIdentSlice(src[var_name_start..]));
            },
            else => continue,
        }
    } else error.NoVarFound;
}

pub const InitStruct = struct {
    allocator: Allocator,

    pub fn parse(src: []const u8, i: usize, allocator: Allocator) !@This() {
        var start = i;
        while (start < src.len and src[start] != '{') start += 1;
        if (start >= src.len) return error.UnexpectedEndOfInput;
        start += 1;

        var brace_counter: usize = 1;
        var string_flag: bool = false;
        var end = start;
        while (brace_counter > 0 and end < src.len) {
            switch (src[end]) {
                '"' => if (src[end - 1] != '\\') {
                    string_flag = !string_flag;
                },
                '{' => if (!string_flag) {
                    brace_counter += 1;
                },
                '}' => if (!string_flag) {
                    brace_counter -= 1;
                },
                else => {},
            }

            end += 1;
        }
        if (brace_counter >= 0) return error.BraceMismatch;

        const init_struct = src[start..end];
        std.debug.print("{s}\n", .{init_struct});

        return .{
            .allocator = allocator,
        };
    }
};
