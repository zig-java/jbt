const std = @import("std");

pub const Version = std.meta.Tuple(&[_]type{ usize, usize });

pub const CompileStep = struct {
    pub const base_id = .install_dir;

    const Self = @This();

    step: std.build.Step,
    builder: *std.build.Builder,
    /// Version of the Java source
    source_version: Version,
    /// Version of the target JVM bytecode
    target_version: Version,
    /// Name of the jar (name.jar)
    name: []const u8,
    /// Bin path
    output_path: []const u8,
    /// Classpath
    classpath: std.ArrayList([]const u8),
    /// Classes that should be compiled
    classes: std.ArrayList([]const u8),

    /// List of classes that should be compiled
    pub fn init(builder: *std.build.Builder, name_raw: []const u8, version: Version) *Self {
        const name = builder.dupe(name_raw);

        const self = builder.allocator.create(Self) catch unreachable;
        self.* = Self{
            .step = std.build.Step.init(base_id, name, builder.allocator, make),
            .builder = builder,
            .source_version = version,
            .target_version = version,
            .name = name,
            .output_path = std.fs.path.join(self.builder.allocator, &[_][]const u8{ self.builder.install_prefix, builder.fmt("{s}-bin", .{self.name}) }) catch unreachable,
            .classpath = std.ArrayList([]const u8).init(builder.allocator),
            .classes = std.ArrayList([]const u8).init(builder.allocator),
        };
        return self;
    }

    pub fn install(self: *Self) void {
        self.builder.getInstallStep().dependOn(&self.step);
    }

    pub fn addClass(self: *Self, path: []const u8) void {
        self.classes.append(path) catch unreachable;
    }

    pub fn jar(self: *Self) *JarStep {
        return JarStep.init(self.builder, self.name, self.output_path);
    }

    fn make(step: *std.build.Step) !void {
        const self = @fieldParentPtr(CompileStep, "step", step);
        try self.build();
    }

    fn build(self: *Self) !void {
        const builder = self.builder;

        var java_args = std.ArrayList([]const u8).init(builder.allocator);
        defer java_args.deinit();

        try java_args.append("javac");

        try java_args.append("-verbose");

        try java_args.append("-d");
        try java_args.append(self.output_path);

        try java_args.append("-source");
        try java_args.append(builder.fmt("{d}", .{self.source_version[0]}));

        try java_args.append("-target");
        try java_args.append(builder.fmt("{d}", .{self.target_version[0]}));

        for (self.classes.items) |class| {
            try java_args.append(class);
        }

        const child = std.ChildProcess.init(java_args.items, self.builder.allocator) catch unreachable;
        defer child.deinit();

        child.stderr_behavior = .Pipe;
        child.env_map = self.builder.env_map;

        child.spawn() catch |err| {
            std.log.warn("Unable to spawn {s}: {s}\n", .{ java_args.items[0], @errorName(err) });
            return err;
        };

        var progress = std.Progress{};
        const root_node = progress.start(self.builder.fmt("{s}", .{self.name}), 0) catch |err| switch (err) {
            // TODO still run tests in this case
            error.TimerUnsupported => @panic("timer unsupported"),
        };

        var reader = child.stderr.?.reader();
        var buf: [256]u8 = undefined;
        while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
            if (std.mem.startsWith(u8, line, "[")) {
                var test_node = root_node.start(line, 0);
                test_node.activate();
                progress.refresh();
                test_node.end();
                // root_node.setEstimatedTotalItems();
                // root_node.completeOne();
            } else {
                try std.io.getStdErr().writer().print("{s}\n", .{line});
            }
        }
        _ = try child.wait();
        root_node.end();
    }
};

pub const JarStep = struct {
    pub const base_id = .run;

    const Self = @This();

    step: std.build.Step,
    builder: *std.build.Builder,
    /// Name of the jar (name.jar)
    name: []const u8,
    /// Directory of compiled class files
    bin_path: []const u8,
    /// Output path
    output_path: []const u8,

    pub fn init(builder: *std.build.Builder, name_raw: []const u8, bin_path_raw: []const u8) *Self {
        const name = builder.dupe(name_raw);
        const bin_path = builder.dupe(bin_path_raw);

        const self = builder.allocator.create(Self) catch unreachable;
        self.* = Self{
            .step = std.build.Step.init(base_id, name, builder.allocator, make),
            .builder = builder,
            .name = name,
            .bin_path = bin_path,
            .output_path = std.fs.path.join(self.builder.allocator, &[_][]const u8{ self.builder.install_prefix, "jar", builder.fmt("{s}.jar", .{self.name}) }) catch unreachable,
        };
        return self;
    }

    fn make(step: *std.build.Step) !void {
        const self = @fieldParentPtr(JarStep, "step", step);
        const builder = self.builder;

        std.fs.cwd().makePath(self.output_path) catch unreachable;

        var java_args = std.ArrayList([]const u8).init(builder.allocator);
        defer java_args.deinit();

        try java_args.append("jar");
        try java_args.append("cf");
        try java_args.append(self.output_path);
        try java_args.append(std.fs.path.join(self.builder.allocator, &[_][]const u8{ self.bin_path, "*" }) catch unreachable);

        try builder.spawnChild(java_args.items);
    }
};
