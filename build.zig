const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const enable_asserts = b.option(
        bool,
        "enable_asserts",
        "Enable asserts",
    ) orelse false;
    const enable_statistics = b.option(
        bool,
        "enable_statistics",
        "Enable statistics",
    ) orelse false;
    const enable_decommit = b.option(
        bool,
        "enable_decommit",
        "Enable decommitting memory pages",
    ) orelse true;
    const enable_unmap = b.option(
        bool,
        "enable_unmap",
        "Enable unmapping memory pages",
    ) orelse true;
    const enable_validate_args = b.option(
        bool,
        "enable_validate_args",
        "Enable validation of args to public entry points",
    ) orelse false;

    const rpmalloc_mod = b.addModule("rpmalloc", .{
        .root_source_file = b.path("rpmalloc.zig"),
        .target = target,
        .optimize = optimize,
    });

    const rpmalloc_dep = b.dependency("rpmalloc", .{});
    rpmalloc_mod.addIncludePath(rpmalloc_dep.path("rpmalloc"));

    const rpmalloc = b.addStaticLibrary(.{
        .name = "rpmalloc-lib",
        .target = target,
        .optimize = optimize,
    });

    switch (builtin.os.tag) {
        .linux => rpmalloc.linkSystemLibrary("pthread"),
        .windows, .macos => {},
        else => @compileError("Unsupported OS"),
    }
    rpmalloc.linkLibC();
    rpmalloc.addCSourceFiles(.{
        .root = rpmalloc_dep.path("rpmalloc"),
        .files = &.{"rpmalloc.c"},
        .flags = &switch (builtin.os.tag) {
            .windows => .{},
            .linux => .{"-D_GNU_SOURCE=1"},
            .macos => .{ "-Wno-padded", "-Wno-documentation-unknown-command", "-Wno-static-in-inline" },
            else => @compileError("Unsupported OS"),
        },
    });

    inline for (.{
        .{ "ENABLE_ASSERTS", enable_asserts },
        .{ "ENABLE_STATISTICS", enable_statistics },
        .{ "ENABLE_DECOMMIT", enable_decommit },
        .{ "ENABLE_UNMAP", enable_unmap },
        .{ "ENABLE_VALIDATE_ARGS", enable_validate_args },
    }) |define| rpmalloc.root_module.addCMacro(define[0], if (define[1]) "1" else "0");

    b.installArtifact(rpmalloc);
}
