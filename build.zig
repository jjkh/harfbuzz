const std = @import("std");

// const version = std.SemanticVersion.parse(@import("build.zig.zon").version) catch unreachable;
const version: std.SemanticVersion = std.SemanticVersion{ .major = 11, .minor = 3, .patch = 3, .pre = "dev" };

pub fn build(b: *std.Build) !void {
    const upstream = b.dependency("harfbuzz", .{});
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const coretext_enabled = b.option(bool, "enable-coretext", "Build coretext") orelse false;
    const freetype_enabled = b.option(bool, "enable-freetype", "Build freetype") orelse true;

    const lib = b.addLibrary(.{
        .name = "harfbuzz",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            // https://github.com/ziglang/zig/issues/5312#issuecomment-1219056640
            .link_libcpp = target.result.abi != .msvc,
        }),
        .version = version,
    });
    lib.addIncludePath(upstream.path("src"));

    if (freetype_enabled) {
        const freetype_opts = .{ .target = target, .optimize = optimize, .@"enable-libpng" = true };
        if (b.lazyDependency("freetype", freetype_opts)) |freetype_dep| {
            lib.linkLibrary(freetype_dep.artifact("freetype"));
            lib.addIncludePath(freetype_dep.builder.dependency("freetype", .{}).path("include"));
        }
    }

    var flags: std.ArrayListUnmanaged([]const u8) = .empty;
    defer flags.deinit(b.allocator);
    try flags.appendSlice(b.allocator, &.{
        "-DHAVE_STDBOOL_H",
    });
    if (target.result.os.tag != .windows) {
        try flags.appendSlice(b.allocator, &.{
            "-DHAVE_UNISTD_H",
            "-DHAVE_SYS_MMAN_H",
            "-DHAVE_PTHREAD=1",
        });
    }
    if (freetype_enabled) try flags.appendSlice(b.allocator, &.{
        "-DHAVE_FREETYPE=1",

        // Let's just assume a new freetype
        "-DHAVE_FT_GET_VAR_BLEND_COORDINATES=1",
        "-DHAVE_FT_SET_VAR_BLEND_COORDINATES=1",
        "-DHAVE_FT_DONE_MM_VAR=1",
        "-DHAVE_FT_GET_TRANSFORM=1",
    });
    if (coretext_enabled) {
        try flags.appendSlice(b.allocator, &.{"-DHAVE_CORETEXT=1"});
        lib.linkFramework("CoreText");
    }

    lib.addCSourceFile(.{
        .file = upstream.path("src/harfbuzz.cc"),
        .flags = flags.items,
    });
    lib.installHeadersDirectory(
        upstream.path("src"),
        "",
        .{ .include_extensions = &.{".h"} },
    );

    b.installArtifact(lib);
}
