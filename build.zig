const std = @import("std");
const jbt = @import("jbt.zig");

pub fn build(builder: *std.build.Builder) void {
    var bin = jbt.CompileStep.init(builder, "foo", .{ 16, 0 });
    bin.addClass("demo/src/demo/Foo.java");
    bin.install();

    // var run_cmd = bin.run();
    // run_cmd.step.dependOn(builder.getInstallStep());

    // const run_step = builder.step("run", "Runs a JAR");
    // run_step.dependOn(&run_cmd.step);

    var jar_cmd = bin.jar();
    jar_cmd.step.dependOn(builder.getInstallStep());

    const jar_step = builder.step("jar", "Create a JAR");
    jar_step.dependOn(&jar_cmd.step);
}
