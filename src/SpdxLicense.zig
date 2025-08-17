const std = @import("std");

// https://dwheeler.com/essays/floss-license-slide.html

pub const Token = struct {
    tag: Tag,
    start: usize,
    end: usize,

    pub const Tag = enum {
        @"license-id",
        @"license-ref",
        with,
        @"and",
        @"or",
        l_brace,
        r_brace,
        @"+",
    };

    pub fn get(self: *const @This(), s: []const u8) ?[]const u8 {
        if (self.end > s.len) return null;
        return s[self.start..self.end];
    }

    pub fn getPrecedence(self: *const @This()) u8 {
        return switch (self.tag) {
            .@"+" => 1,
            .with => 2,
            .@"and" => 3,
            .@"or" => 4,
            else => 5,
        };
    }

    pub fn isOperator(self: *const @This()) bool {
        return switch (self.tag) {
            .@"+", .with, .@"and", .@"or" => true,
            else => false,
        };
    }
};

pub const TreeNode = struct {
    pub const Tag = enum {
        /// main_token is the expression
        simple,
        /// `lhs` "+". main_token is the "+"
        @"+",
        /// `lhs`"WITH" `rhs`. main_token is the "WITH"
        with,
        /// `lhs`"AND" `rhs`. main_token is the "AND"
        @"and",
        /// `lhs`"OR" `rhs`. main_token is the "OR"
        @"or",
    };

    tag: Tag,
    main_token: usize,
    lhs: ?*TreeNode = null,
    rhs: ?*TreeNode = null,

    pub fn mainTokenString(self: *const @This(), tree: *const Tree) ?[]const u8 {
        const t = tree.tokens.items[self.main_token];
        return t.get(tree.source);
    }

    pub fn deinit(self: *const @This(), allocator: std.mem.Allocator) void {
        if (self.lhs) |lhs| {
            lhs.deinit(allocator);
            allocator.destroy(lhs);
        }
        if (self.rhs) |rhs| {
            rhs.deinit(allocator);
            allocator.destroy(rhs);
        }
    }
};

pub const Tree = struct {
    /// Reference to externally-owned data.
    source: []const u8,
    tokens: std.ArrayList(Token),
    root_node: *TreeNode,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *const @This()) void {
        self.tokens.deinit();
        self.root_node.deinit(self.allocator);
        self.allocator.destroy(self.root_node);
    }

    fn extractTokens(a: std.mem.Allocator, s: []const u8) !std.ArrayList(Token) {
        var tokens = std.ArrayList(Token).init(a);
        errdefer tokens.deinit();
        //var nodes = std.ArrayList(Node).init(a);
        //errdefer nodes.deinit();

        var i: usize = 0;
        while (true) {
            const start = i;
            while (i < s.len) : (i += 1) {
                if (!isValidTokenByte(s[i])) break;
            }
            const end = i;

            if (end - start > 0) {
                if (std.mem.eql(u8, "WITH", s[start..end])) {
                    try tokens.append(.{
                        .tag = .with,
                        .start = start,
                        .end = end,
                    });
                } else if (std.mem.eql(u8, "AND", s[start..end])) {
                    try tokens.append(.{
                        .tag = .@"and",
                        .start = start,
                        .end = end,
                    });
                } else if (std.mem.eql(u8, "OR", s[start..end])) {
                    try tokens.append(.{
                        .tag = .@"or",
                        .start = start,
                        .end = end,
                    });
                } else {
                    try tokens.append(.{
                        .tag = .@"license-id",
                        .start = start,
                        .end = end,
                    });
                }
            } else if (start < s.len) {
                if (s[start] == '(') {
                    try tokens.append(.{
                        .tag = .l_brace,
                        .start = start,
                        .end = start + 1,
                    });
                } else if (s[start] == ')') {
                    try tokens.append(.{
                        .tag = .r_brace,
                        .start = start,
                        .end = start + 1,
                    });
                } else if (s[start] == '+') {
                    try tokens.append(.{
                        .tag = .@"+",
                        .start = start,
                        .end = start + 1,
                    });
                } else if (s[start] == ' ') {} else return error.MalformedExpression;
                i += 1;
            } else break;
        }

        return tokens;
    }

    /// Build Syntax Tree using the Shunting yard algorithm.
    ///
    /// https://en.wikipedia.org/wiki/Shunting_yard_algorithm
    pub fn parse_expression(
        s: []const u8,
        tokens: std.ArrayList(Token),
        allocator: std.mem.Allocator,
    ) !*TreeNode {
        _ = s;
        var output = std.ArrayList(usize).init(allocator);
        defer output.deinit();
        var operators = std.ArrayList(usize).init(allocator);
        defer operators.deinit();

        for (tokens.items, 0..) |token, i| {
            if (token.isOperator()) {
                while (operators.items.len > 0 and tokens.items[operators.items[operators.items.len - 1]].getPrecedence() <= token.getPrecedence()) {
                    const t = operators.pop() orelse return error.NoToken;
                    try output.append(t);
                }
                try operators.append(i);
            } else if (token.tag == .l_brace) {
                try operators.append(i);
            } else if (token.tag == .r_brace) {
                while (operators.items.len > 0 and tokens.items[operators.items[operators.items.len - 1]].tag != .l_brace) {
                    const t = operators.pop() orelse return error.NoToken;
                    try output.append(t);
                }
                const t = operators.pop(); // pop '('
                if (t == null or tokens.items[t.?].tag != .l_brace) return error.MissingLBrace;
            } else { // simple value
                try output.append(i);
            }

            // Debug output:
            //std.debug.print("output: ", .{});
            //for (output.items) |j| {
            //    const item = tokens.items[j];
            //    std.debug.print("{s}, ", .{s[item.start..item.end]});
            //}
            //std.debug.print("\n", .{});
            //std.debug.print("operators: ", .{});
            //for (operators.items) |j| {
            //    const item = tokens.items[j];
            //    std.debug.print("{s}, ", .{s[item.start..item.end]});
            //}
            //std.debug.print("\n", .{});
        }

        while (operators.pop()) |token| try output.append(token);

        // ---------------------

        // License expressions are quite small, i.e. we don't need
        // to implement this super memory efficient (e.g. using a
        // linear data structure and indices) and can just create
        // a tree with pointers to the child nodes.
        //
        // This stack is used to keep track of the nodes and
        // gradually build the tree. At the end, we expect the
        // stack to have a size of 1, where the only element is
        // the root node of the tree.
        var stack = std.ArrayList(*TreeNode).init(allocator);
        errdefer {
            for (stack.items) |item| {
                item.deinit(allocator);
                allocator.destroy(item);
            }
            stack.deinit();
        }

        for (output.items) |i| {
            const tag = tokens.items[i].tag;
            switch (tag) {
                .@"license-id", .@"license-ref" => {
                    const n = try allocator.create(TreeNode);
                    errdefer allocator.destroy(n);
                    n.* = .{
                        .tag = .simple,
                        .main_token = i,
                    };
                    try stack.append(n);
                },
                .l_brace, .r_brace => {}, // we removed them in the prev step
                .@"+" => {
                    const lhs = stack.pop() orelse return error.MissingNode;
                    if (lhs.tag != .simple) return error.LhsNotASimpleExpression;
                    const n = try allocator.create(TreeNode);
                    errdefer allocator.destroy(n);
                    n.* = .{
                        .tag = .@"+",
                        .main_token = i,
                        .lhs = lhs,
                    };
                    try stack.append(n);
                },
                else => { // and, or, with
                    const t: TreeNode.Tag = switch (tag) {
                        .@"and" => .@"and",
                        .@"or" => .@"or",
                        else => .with,
                    };

                    const rhs = stack.pop() orelse return error.MissingNode;
                    const lhs = stack.pop() orelse return error.MissingNode;
                    const n = try allocator.create(TreeNode);
                    errdefer allocator.destroy(n);
                    n.* = .{
                        .tag = t,
                        .main_token = i,
                        .lhs = lhs,
                        .rhs = rhs,
                    };
                    try stack.append(n);
                },
            }
        }

        if (stack.items.len != 1) return error.MalformedExpression;

        const ret = stack.items[0];
        stack.deinit();
        return ret;
    }

    pub fn new(a: std.mem.Allocator, s: []const u8) !@This() {
        const tokens = try extractTokens(a, s);
        errdefer tokens.deinit();
        const root_node = try parse_expression(s, tokens, a);

        return .{
            .source = s,
            .tokens = tokens,
            .root_node = root_node,
            .allocator = a,
        };
    }

    fn isValidTokenByte(b: u8) bool {
        return switch (b) {
            'a'...'z',
            'A'...'Z',
            '0'...'9',
            '-',
            '.',
            => true,
            else => false,
        };
    }
};

//pub const Token = struct {
//    id: TokenId,
//    s: []const u8,
//    start: usize,
//    end: usize,
//};
//
//pub const TokenIterator = struct {
//    license: []const u8,
//    i: usize = 0,
//
//    pub fn new(s: []const u8) @This() {
//        return .{
//            .s = s,
//        };
//    }
//
//    pub fn next(self: *@This()) ?Token {
//        if (self.i >= self.license.len) return null;
//
//        const start = self.i;
//
//        if (self.license[start] == '(') {
//            self.i += 1;
//            return .{
//                .id = .l_brace,
//                .s = self.license[start..self.i],
//                .start = start,
//                .end = self.i,
//            };
//        } else if (self.license[start] == ')') {
//            self.i += 1;
//            return .{
//                .id = .r_brace,
//                .s = self.license[start..self.i],
//                .start = start,
//                .end = self.i,
//            };
//        }
//
//        var end = start;
//        while (end < self.license.len and self.license[end] != ' ' and self.license[end] != '(' and self.license[end] != ')') : (end += 1) {}
//
//        const t = self.license[start..end];
//
//        const token: Token = if (std.mem.eql(u8, t, "WITH")) blk: {
//            break :blk .{ .id = .with, .s = t, .start = start, .end = end };
//        } else if (std.mem.eql(u8, t, "AND")) blk: {
//            break :blk .{ .id = .@"and", .s = t, .start = start, .end = end };
//        } else if (std.mem.eql(u8, t, "OR")) blk: {
//            break :blk .{ .id = .@"or", .s = t, .start = start, .end = end };
//        } else if (std.mem.startsWith(u8, t, "DocumentRef-")) blk: {
//            break :blk .{ .id = .unknown, .s = t, .start = start, .end = end };
//        } else if (std.mem.startsWith(u8, t, "LicenseRef-")) blk: {
//            break :blk .{ .id = .unknown, .s = t, .start = start, .end = end };
//        } else blk: {
//            const ids = t;
//
//            const plus = t.len > 0 and t[t.len - 1] == '+';
//            if (plus) ids = t[0 .. t.len - 1];
//
//            const valid = idStringIsValid(ids);
//            if (!valid) break :blk .{ .id = .unknown, .s = t, .start = start, .end = end };
//        };
//
//        while (end < self.license.len and self.license[end] == ' ') : (end += 1) {}
//        self.i = end;
//
//        return token;
//    }
//
//    fn idStringIsValid(ids: []const u8) bool {
//        for (ids) |b| {
//            switch (b) {
//                'a'...'z',
//                'A'...'Z',
//                '0'...'9',
//                '-',
//                '.',
//                => {},
//                else => return false,
//            }
//        }
//
//        return true;
//    }
//};

// /////////////////// Tests /////////////////////////////

const TokenTestCase = struct {
    expr: []const u8,
    tokens: []const []const u8,
};

const token_test_cases: []const TokenTestCase = &.{
    .{
        .expr = "LGPL-2.1-only OR MIT OR BSD-3-Clause",
        .tokens = &.{
            "LGPL-2.1-only",
            "OR",
            "MIT",
            "OR",
            "BSD-3-Clause",
        },
    },
    .{
        .expr = "GPL-2.0-or-later WITH Bison-exception-2.2",
        .tokens = &.{
            "GPL-2.0-or-later",
            "WITH",
            "Bison-exception-2.2",
        },
    },
    .{
        .expr = "MIT AND (LGPL-2.1-or-later OR BSD-3-Clause)",
        .tokens = &.{
            "MIT",
            "AND",
            "(",
            "LGPL-2.1-or-later",
            "OR",
            "BSD-3-Clause",
            ")",
        },
    },
};

test "parse expression into tokens" {
    const a = std.testing.allocator;

    for (token_test_cases) |token_test| {
        const t = try Tree.new(a, token_test.expr);
        defer t.deinit();

        for (t.tokens.items, token_test.tokens) |t1, t2| {
            try std.testing.expectEqualSlices(u8, t.source[t1.start..t1.end], t2);
        }
    }
}

test "generate tree #1" {
    const a = std.testing.allocator;

    const t = try Tree.new(a, "MIT AND (LGPL-2.1-or-later OR BSD-3-Clause)");
    defer t.deinit();

    try std.testing.expectEqual(TreeNode.Tag.@"and", t.root_node.tag);
    const lhs = t.root_node.lhs.?;
    try std.testing.expectEqual(TreeNode.Tag.simple, lhs.tag);
    try std.testing.expectEqualSlices(u8, "MIT", lhs.mainTokenString(&t).?);

    const rhs = t.root_node.rhs.?;
    try std.testing.expectEqual(TreeNode.Tag.@"or", rhs.tag);
    {
        const lhs2 = rhs.lhs.?;
        try std.testing.expectEqual(TreeNode.Tag.simple, lhs2.tag);
        try std.testing.expectEqualSlices(u8, "LGPL-2.1-or-later", lhs2.mainTokenString(&t).?);

        const rhs2 = rhs.rhs.?;
        try std.testing.expectEqual(TreeNode.Tag.simple, rhs2.tag);
        try std.testing.expectEqualSlices(u8, "BSD-3-Clause", rhs2.mainTokenString(&t).?);
    }
}

test "generate tree #2" {
    const a = std.testing.allocator;

    const t = try Tree.new(a, "(LGPL-2.1-or-later OR BSD-3-Clause) AND MIT");
    defer t.deinit();

    try std.testing.expectEqual(TreeNode.Tag.@"and", t.root_node.tag);
    const rhs = t.root_node.rhs.?;
    try std.testing.expectEqual(TreeNode.Tag.simple, rhs.tag);
    try std.testing.expectEqualSlices(u8, "MIT", rhs.mainTokenString(&t).?);

    const lhs = t.root_node.lhs.?;
    try std.testing.expectEqual(TreeNode.Tag.@"or", lhs.tag);
    {
        const lhs2 = lhs.lhs.?;
        try std.testing.expectEqual(TreeNode.Tag.simple, lhs2.tag);
        try std.testing.expectEqualSlices(u8, "LGPL-2.1-or-later", lhs2.mainTokenString(&t).?);

        const rhs2 = lhs.rhs.?;
        try std.testing.expectEqual(TreeNode.Tag.simple, rhs2.tag);
        try std.testing.expectEqualSlices(u8, "BSD-3-Clause", rhs2.mainTokenString(&t).?);
    }
}

test "generate tree #3" {
    const a = std.testing.allocator;

    const t = try Tree.new(a, "MIT AND LGPL-2.1-or-later OR BSD-3-Clause AND Apache-2.0");
    defer t.deinit();

    try std.testing.expectEqual(TreeNode.Tag.@"or", t.root_node.tag);

    const lhs = t.root_node.lhs.?;
    try std.testing.expectEqual(TreeNode.Tag.@"and", lhs.tag);
    {
        const lhs2 = lhs.lhs.?;
        try std.testing.expectEqual(TreeNode.Tag.simple, lhs2.tag);
        try std.testing.expectEqualSlices(u8, "MIT", lhs2.mainTokenString(&t).?);

        const rhs2 = lhs.rhs.?;
        try std.testing.expectEqual(TreeNode.Tag.simple, rhs2.tag);
        try std.testing.expectEqualSlices(u8, "LGPL-2.1-or-later", rhs2.mainTokenString(&t).?);
    }

    const rhs = t.root_node.rhs.?;
    try std.testing.expectEqual(TreeNode.Tag.@"and", rhs.tag);
    {
        const lhs2 = rhs.lhs.?;
        try std.testing.expectEqual(TreeNode.Tag.simple, lhs2.tag);
        try std.testing.expectEqualSlices(u8, "BSD-3-Clause", lhs2.mainTokenString(&t).?);

        const rhs2 = rhs.rhs.?;
        try std.testing.expectEqual(TreeNode.Tag.simple, rhs2.tag);
        try std.testing.expectEqualSlices(u8, "Apache-2.0", rhs2.mainTokenString(&t).?);
    }
}

test "malformed expression #1" {
    const a = std.testing.allocator;

    try std.testing.expectError(error.MalformedExpression, Tree.new(a, "MIT LGPL-2.1-or-later OR BSD-3-Clause AND Apache-2.0"));

    try std.testing.expectError(error.MalformedExpression, Tree.new(a, "MIT AND LGPL-2.1-or-later  BSD-3-Clause AND Apache-2.0"));

    try std.testing.expectError(error.MissingLBrace, Tree.new(a, "MIT AND LGPL-2.1-or-later OR) BSD-3-Clause AND Apache-2.0"));
}
