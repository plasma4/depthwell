const std = @import("std");

// Run zig build normally, and zig build -Doptimize=ReleaseFast for a quick production version test.
// Use zig build -Dwasm-opt to use ReleaseFast AND highly aggressive wasm-opt (from Binaryen).
// Use zig build -Dgen-enums as well to automatically construct src/enums.ts and zig test "zig/root.zig" to run all tests across the codebase.
// (Add --memory64 for 64-bit builds.)

pub fn build(b: *std.Build) void {
    // TODO add in wasm-opt for ReleaseFast builds for even more optimization!
    b.install_path = ".";
    const aseprite_path = b.option([]const u8, "aseprite", "Path to the Aseprite executable (default: aseprite in PATH)") orelse
        b.findProgram(&.{"aseprite"}, &.{}) catch null;
    const gen_enums = b.option(bool, "gen-enums", "Regenerate TypeScript enum definitions (default: no)") orelse false; // -Dgen-enums
    const wasm_opt = b.option(bool, "wasm-opt", "Add a very aggressive pass of optimizations provided by wasm-opt from Binaryen, forcing optimization level to ReleaseFast") orelse false; // -Dgen-enums
    const memory64 = b.option(bool, "memory64", "Utilize Memory64 (and enable relaxed SIMD)") orelse false; // -Dmemory64
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = if (memory64) .wasm64 else .wasm32, // WASM 32-bit. Works with 64-bit too (if Memory64 is needed in the future).
            .os_tag = .freestanding,
            .cpu_features_add = std.Target.wasm.featureSet(if (memory64) &.{ // We add features that are almost certainly supported by a browser that already supports WebGPU.
                .simd128,
                .tail_call,
                .bulk_memory,
                .mutable_globals,
                .sign_ext,
                .nontrapping_fptoint,
                .reference_types,
                .multivalue,
                .exception_handling,
                .extended_const,
                .relaxed_simd,
            } else &.{ // We add features that are almost certainly supported by a browser that already supports WebGPU.
                .simd128,
                .tail_call,
                .bulk_memory,
                .mutable_globals,
                .sign_ext,
                .nontrapping_fptoint,
                .reference_types,
                .multivalue,
                .exception_handling,
                .extended_const,
            }),
        },
    });

    const optimize: std.builtin.OptimizeMode = if (wasm_opt) .ReleaseFast else b.standardOptimizeOption(.{});

    const module = b.createModule(.{
        .root_source_file = b.path("zig/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Main WASM game build
    const exe = b.addExecutable(.{ .name = "engine", .root_module = module });

    if (optimize == .Debug) {
        exe.root_module.strip = false; // try to reduce any WASM optimization
        exe.lto = .none;
        exe.export_table = true;

        // having these lines uncommented seems to freak the Zig compiler out a lot, so best to not use these for now
        // exe.use_llvm = false;
        // exe.use_lld = false;
    } else if (optimize == .ReleaseFast) {
        exe.root_module.single_threaded = true;
        exe.root_module.stack_check = false;
        exe.lto = .full;
    }
    exe.rdynamic = true; // export functions with "export" keyword
    exe.stack_size = 8 * 65536; // 512KiB, can increase as necessary

    // removed since Zig manages pointers automatically
    // exe.global_base = 8;

    const install_wasm = b.addInstallFileWithDir(
        exe.getEmittedBin(),
        .{ .custom = "public/" },
        "main.wasm",
    );
    b.getInstallStep().dependOn(&install_wasm.step); // install

    if (wasm_opt) {
        const optimize_wasm = b.addSystemCommand(&.{ "wasm-opt", "public/main.wasm", "-o", "public/main.wasm", "-O4" });

        // Add all those specific flags for more optimization!
        optimize_wasm.addArgs(&.{
            "--strip-debug",
            "--strip-dwarf",
            "--strip-producers",
            "--optimize-instructions",
            "--flatten",
            "--rereloop",
            "--enable-simd",
            "--enable-sign-ext",
            "--enable-tail-call",
            "--enable-bulk-memory",
            "--enable-multivalue",
            "--enable-reference-types",
            "--converge",
            "--gufa-optimizing",
            "--traps-never-happen",
            "--ignore-implicit-traps",
            "--limit-segments",
            "--closed-world",
            "--inline-functions-with-loops",
            "--inline-max-combined-binary-size=100000",
            "--directize",
            "--memory-packing",
            "--optimize-added-constants-propagate",
            "--flexible-inline-max-function-size=100",
            "--one-caller-inline-max-function-size=1",
            "--roundtrip",
            "--low-memory-unused",
        });

        if (memory64) {
            optimize_wasm.addArg("--enable-memory64");
            optimize_wasm.addArg("--enable-relaxed-simd");
        }

        // This ensures wasm-opt runs AFTER the file is installed to public/main.wasm
        optimize_wasm.step.dependOn(&install_wasm.step);
        b.getInstallStep().dependOn(&optimize_wasm.step);
    }

    if (gen_enums) {
        generateEnums(b, &[_][]const u8{ "zig/root.zig", "zig/types/types.zig", "zig/memory.zig" });
    }

    // validate!
    if (aseprite_path) |path| {
        const export_main = addAsepriteStep(
            b,
            path,
            "aseprite/main.aseprite",
            "main",
            "main.png",
        );
        const export_masked = addAsepriteStep(
            b,
            path,
            "aseprite/main.aseprite",
            "masks",
            "mainMasked.png",
        );

        // Install the generated files from the cache into your src directory
        const install_main = b.addInstallFile(export_main, "public/assets/main.png");
        const install_masked = b.addInstallFile(export_masked, "public/assets/mainMasked.png");

        // Make the WASM build depend on the installation of assets
        exe.step.dependOn(&install_main.step);
        exe.step.dependOn(&install_masked.step);
    } else {
        std.debug.print("Aseprite executable not found; skipping step. Either add to your system PATH or use -Daseprite.", .{});
    }
}

/// Handles `.aseprite` file exports automatically.
fn addAsepriteStep(
    b: *std.Build,
    aseprite_exe: []const u8,
    input_path: []const u8,
    layer_name: []const u8,
    out_filename: []const u8,
) std.Build.LazyPath {
    const run_cmd = b.addSystemCommand(&.{aseprite_exe});
    run_cmd.addArg("-b");
    if (layer_name.len > 0) {
        run_cmd.addArgs(&.{ "--layer", layer_name });
    } else {
        // run_cmd.addArg("--all-layers");
        @panic("Layer name must be non-empty!");
    }

    run_cmd.addFileArg(b.path(input_path));
    run_cmd.addArgs(&.{
        "--sheet-type",
        "rows",
        "--sheet-columns",
        "8",
    });
    run_cmd.addArg("--sheet");
    const output = run_cmd.addOutputFileArg(out_filename);

    // _ = run_cmd.captureStdOut(.{});
    // _ = run_cmd.captureStdErr(.{});
    return output;
}

/// Updates `enums.ts` automatically. Only called by `build()` if the `-Dgen-enums` flag is passed.
fn generateEnums(b: *std.Build, paths: []const []const u8) void {
    const cache_root = b.cache_root.path orelse ".";
    const cache_path = b.pathJoin(&.{ cache_root, "content_hashes.txt" });
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});

    for (paths) |path| {
        const content = b.build_root.handle.readFileAlloc(
            b.graph.io,
            path,
            b.allocator,
            .unlimited,
        ) catch |err| {
            std.debug.panic("Warning: skipping enum generation due to being unable to read {s}: {any}\n", .{ path, err });
            return;
        };
        defer b.allocator.free(content);
        hasher.update(content);
    }

    var current_hash_binary: [32]u8 = undefined;
    hasher.final(&current_hash_binary);

    const current_hash_hex: []const u8 = &std.fmt.bytesToHex(current_hash_binary, .lower);
    const old_hash_hex = b.build_root.handle.readFileAlloc(
        b.graph.io,
        cache_path,
        b.allocator,
        .limited(128), // extra buffer
    ) catch |err| blk: {
        if (err != error.FileNotFound) {
            std.debug.panic("Warning: Could not read cache: {any}\n", .{err});
        }
        break :blk b.allocator.alloc(u8, 0) catch "";
    };

    // @import("zig/logger.zig").quickWarn(.{ current_hash_hex, old_hash_hex, std.mem.eql(u8, current_hash_hex, old_hash_hex) });
    defer if (old_hash_hex.len > 0) b.allocator.free(old_hash_hex);

    // compare array to slice and update content hash if necessary in generate_types.zig
    if (std.mem.eql(u8, current_hash_hex, old_hash_hex)) {
        return;
    }

    // now actually update the types if necessary
    const gen_tool = b.addExecutable(.{
        .name = "generate_types",
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig/generate_types.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });

    // Create exactly ONE module for the game code
    // const depthwell_mod = b.createModule(.{
    //     .root_source_file = b.path("zig/root.zig"),
    // });

    // // The tool only needs to see the game root
    // gen_tool.root_module.addImport("depthwell", depthwell_mod);

    const run_enums = b.addRunArtifact(gen_tool);
    run_enums.has_side_effects = true;

    // Pass the strings as arguments to the executable
    run_enums.addArgs(&.{
        cache_root,
        cache_path,
        current_hash_hex,
    });

    const generated_enums = run_enums.captureStdOut(.{});
    const install_ts = b.addInstallFileWithDir(
        generated_enums,
        .{ .custom = "src/" },
        "enums.ts",
    );

    // Add to the main install step
    b.getInstallStep().dependOn(&install_ts.step);
}
