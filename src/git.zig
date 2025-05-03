const std = @import("std");
const Allocator = std.mem.Allocator;

const ini = @import("ini");

const misc = @import("misc.zig");

pub const GitConfig = struct {
    core: struct {
        repositoryformatversion: usize = 0,
        filemode: bool = true,
        bare: bool = false,
        logallrefupdates: bool = true,
    } = .{},
    remote_origin: struct {
        url: ?[]const u8 = null,
        fetch: ?[]const u8 = null,
    } = .{},
    allocator: Allocator,

    pub fn deinit(self: *const @This()) void {
        if (self.remote_origin.url) |url| self.allocator.free(url);
        if (self.remote_origin.fetch) |fetch| self.allocator.free(fetch);
    }

    //pub fn purlFromRemote(self: *const @This(), allocator: Allocator) !?[]const u8 {
    //    // example: pkg:github/Hejsil/zig-clap@0.10.0
    //    if (self.remote_origin.url == null) return null;

    //
    //}

    pub fn load(allocator: Allocator) !@This() {
        const sections = enum {
            core,
            remote,
            branch,
            pull,
            unknown,
        };

        var br = try misc.findBuildRoot(allocator, .{});
        defer br.deinit();

        const f = try br.directory.handle.openFile(".git/config", .{});
        defer f.close();

        var parser = ini.parse(allocator, f.reader(), ";#");
        defer parser.deinit();

        var config = @This(){
            .allocator = allocator,
        };

        var cur_section: sections = .unknown;
        while (try parser.next()) |record| {
            switch (record) {
                .section => |heading| {
                    if (std.mem.containsAtLeast(u8, heading, 1, "core"))
                        cur_section = .core
                    else if (std.mem.containsAtLeast(u8, heading, 1, "remote"))
                        cur_section = .remote
                    else if (std.mem.containsAtLeast(u8, heading, 1, "branch"))
                        cur_section = .branch
                    else if (std.mem.containsAtLeast(u8, heading, 1, "pull"))
                        cur_section = .pull
                    else
                        cur_section = .unknown;
                },
                .property => |kv| {
                    switch (cur_section) {
                        .remote => {
                            if (std.mem.eql(u8, kv.key, "url")) {
                                config.remote_origin.url = try allocator.dupe(u8, kv.value);
                            } else if (std.mem.eql(u8, kv.key, "fetch")) {
                                config.remote_origin.fetch = try allocator.dupe(u8, kv.value);
                            }
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        return config;
    }
};
