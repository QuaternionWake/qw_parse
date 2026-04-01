const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const num_parse = b.addModule("num-parse", .{
        .root_source_file = b.path("src/num-parse.zig"),
        .target = target,
        .optimize = optimize,
    });

    const num_format = b.addModule("num-format", .{
        .root_source_file = b.path("src/num-format.zig"),
        .target = target,
        .optimize = optimize,
    });

    const num_parse_tests = b.addTest(.{
        .root_module = num_parse,
    });

    const num_format_tests = b.addTest(.{
        .root_module = num_format,
    });

    const run_num_parse_tests = b.addRunArtifact(num_parse_tests);
    const run_num_format_tests = b.addRunArtifact(num_format_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_num_parse_tests.step);
    test_step.dependOn(&run_num_format_tests.step);
}
