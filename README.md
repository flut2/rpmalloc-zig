# Zig bindings for [rpmalloc](https://github.com/mjansson/rpmalloc)

## Building
Run the following commands:
```sh
cd <project root folder>
zig fetch https://github.com/flut2/rpmalloc-zig/archive/<current_commit>.tar.gz --save=rpmalloc
```

Add the following to your build.zig:
```zig
const rpmalloc_dep = b.dependency("rpmalloc", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("rpmalloc", rpmalloc_dep.module("rpmalloc"));
exe.root_module.linkLibrary(rpmalloc_dep.artifact("rpmalloc-lib"))
```

## Usage
```zig
const std = @import("std");
const rpmalloc = @import("rpmalloc");

pub fn main() !void {
    // Initialize/deinitialize rpmalloc
    rpmalloc.init(.{}, .{});
    defer rpmalloc.deinit();

    // Get a Zig allocator wrapping rpmalloc
    const allocator = rpmalloc.allocator();

    // Allocate as normal
    const dummy = try allocator.alloc(u8, 64);
    defer allocator.free(dummy);

    const thread: std.Thread = try .spawn(.{ .allocator = allocator }, otherThread, .{});
    defer thread.join();
}

fn otherThread(allocator: std.mem.Allocator) void {
    // Initialize/deinitialize rpmalloc's thread storage
    rpmalloc.initThread();
    defer rpmalloc.deinitThread();

    // Continue allocating as normal
    const dummy = try allocator.alloc(u8, 64);
    defer allocator.free(dummy);
}
```
