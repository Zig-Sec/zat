const std = @import("std");

pub const zat = struct {
    pub const Build = struct {
        build: *std.Build,

        args: ?[]const []const u8 = null,

        pub fn standardTargetOptions(b: *Build, args: std.Build.StandardTargetOptionsArgs) std.Build.ResolvedTarget {
            return b.build.standardTargetOptions(args);
        }

        pub fn dependency(b: *Build, name: []const u8, args: anytype) *std.Build.Dependency {
            return b.build.dependency(name, args);
        }

        pub fn createModule(b: *Build, options: std.Build.Module.CreateOptions) *std.Build.Module {
            return b.build.createModule(options);
        }

        pub fn path(b: *Build, sub_path: []const u8) std.Build.LazyPath {
            return b.build.path(sub_path);
        }

        pub fn addExecutable(b: *Build, options: std.Build.ExecutableOptions) *std.Build.Step.Compile {
            return b.build.addExecutable(options);
        }

        pub fn installArtifact(b: *Build, artifact: *std.Build.Step.Compile) void {
            return b.build.installArtifact(artifact);
        }

        pub fn addRunArtifact(b: *Build, exe: *std.Build.Step.Compile) *std.Build.Step.Run {
            return b.build.addRunArtifact(exe);
        }

        pub fn getInstallStep(b: *Build) *std.Build.Step {
            return b.build.getInstallStep();
        }

        pub fn step(b: *Build, name: []const u8, description: []const u8) *std.Build.Step {
            return b.build.step(name, description);
        }

        pub fn addTest(b: *Build, options: std.Build.TestOptions) *std.Build.Step.Compile {
            return b.build.addTest(options);
        }
    };
};
