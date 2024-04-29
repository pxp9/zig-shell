const std = @import("std");
const CFlags = &.{};

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    var bison = b.addSystemCommand(&.{"bison"});
    bison.addArg("--yacc");
    bison.addArg("-b");
    bison.addArg("src/");
    bison.addArg("-d");
    bison.addArg("-o");
    bison.addArg("src/parser/parser.c");
    bison.addArg("src/parser/parser.y");

    var flex = b.addSystemCommand(&.{"flex"});
    flex.addArg("-o");
    flex.addArg("src/parser/scanner.c");
    flex.addArg("src/parser/scanner.l");

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "minishell-zig",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_parser = b.addExecutable(.{
        .name = "parser",
        .root_source_file = b.path("src/main_parser.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.addCSourceFile(.{
        .file = b.path("src/parser/parser.c"),
        .flags = CFlags,
    });
    exe.addCSourceFile(.{
        .file = b.path("src/parser/scanner.c"),
        .flags = CFlags,
    });

    exe.linkLibCpp();
    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);
    b.installArtifact(exe_parser);
    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    const run_parser_cmd = b.addRunArtifact(exe_parser);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
        run_parser_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
    run_step.dependOn(&bison.step);
    run_step.dependOn(&flex.step);

    const run_parser_step = b.step("run_parser", "Run the parser");
    run_parser_step.dependOn(&run_parser_cmd.step);

    var clean_cmd = b.addSystemCommand(&.{"rm"});
    clean_cmd.addArg("-rf");
    clean_cmd.addArg("src/parser/parser.c");
    clean_cmd.addArg("src/parser/parser.h");
    clean_cmd.addArg("src/parser/scanner.c");
    const clean = b.step("clean", "Remove build artifacts");
    clean.dependOn(&clean_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
