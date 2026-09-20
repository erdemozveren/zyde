const std = @import("std");

const builtin = @import("builtin");
const current_zig = builtin.zig_version;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const public_dir = b.option(
        std.Build.LazyPath,
        "public_dir",
        "Directory containing public files",
    ) orelse b.path("example/public");
    // Library
    const mod = b.addModule("zyde", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const embedded_public = embedDir(b, public_dir) catch |err| {
        std.debug.panic(
            "failed to generate embedded_public: {}",
            .{err},
        );
    };

    mod.addAnonymousImport("embedded_public", .{
        .root_source_file = embedded_public,
    });

    // Library dependencies
    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("httpz", httpz.module("httpz"));

    const serde_dep = b.dependency("serde", .{
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("serde", serde_dep.module("serde"));

    const webview_dep = b.dependency("webview", .{
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("webview", webview_dep.module("webview"));

    // Example
    const example_mod = b.createModule(.{
        .root_source_file = b.path("example/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zyde", .module = mod },
        },
    });

    const example_exe = b.addExecutable(.{
        .name = "zyde-example",
        // NOTE: see https://codeberg.org/ziglang/zig/issues/31272
        .use_llvm = true,
        .root_module = example_mod,
    });

    example_exe.root_module.addWin32ResourceFile(.{
        .file = b.path("example/app.rc"),
        .flags = &.{},
    });

    example_exe.subsystem = .Windows;

    // Example step
    const example_step = b.step(
        "example",
        "Build and run the example app",
    );

    const run_cmd = b.addRunArtifact(example_exe);
    example_step.dependOn(&run_cmd.step);

    const install_example = b.addInstallArtifact(example_exe, .{});
    example_step.dependOn(&install_example.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Tests
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const example_tests = b.addTest(.{
        .root_module = example_mod,
    });

    const run_example_tests = b.addRunArtifact(example_tests);

    const test_step = b.step("test", "Run tests");

    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_example_tests.step);
}

fn embedDir(
    b: *std.Build,
    embed_dir: std.Build.LazyPath,
) !std.Build.LazyPath {
    const io = b.graph.io;
    const files = b.addWriteFiles();

    var writer = std.Io.Writer.Allocating.init(b.allocator);
    defer writer.deinit();

    const w = &writer.writer;

    try w.writeAll(
        \\const std = @import("std");
        \\
        \\pub const files = std.StaticStringMap([]const u8).initComptime(.{
        \\
    );

    const embed_path = embed_dir.getPath2(b, null);

    var dir = try std.Io.Dir.openDirAbsolute(io, embed_path, .{
        .iterate = true,
    });
    defer dir.close(io);

    var walker = try dir.walk(b.allocator);
    defer walker.deinit();

    _ = files.addCopyDirectory(embed_dir, "public", .{});

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) {
            continue;
        }

        try w.print(
            "    .{{ \"/{s}\", @embedFile(\"public/{s}\") }},\n",
            .{
                entry.path,
                entry.path,
            },
        );
    }

    try w.writeAll(
        \\});
        \\
        \\pub fn get(path: []const u8) ?[]const u8 {
        \\    return files.get(path);
        \\}
        \\
    );

    const source = try writer.toOwnedSlice();

    return files.add("embedded_dir.zig", source);
}
