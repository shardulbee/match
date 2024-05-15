const std = @import("std");

pub fn build(b: *std.Build) void {
    // const target = b.standardTargetOptions(.{});
    // const optimize = b.standardOptimizeOption(.{});

    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .aarch64,
            .os_tag = .macos,
        },
    });
    const mode = b.standardOptimizeOption(.{ .preferred_optimize_mode = std.builtin.Mode.ReleaseFast });

    const libmatch = b.addSharedLibrary(.{
        .name = "match",
        .root_source_file = .{ .path = "match.zig" },
        .target = target,
        .optimize = mode,
        .version = .{ .major = 0, .minor = 0, .patch = 1 },
    });
    libmatch.addIncludePath("/nix/store/j0jaqv09421wydqmfawcnwvv2f32q86a-python3-3.11.8/include/python3.11/");

    b.installArtifact(libmatch);
}
