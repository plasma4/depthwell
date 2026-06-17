const std = @import("std");
const r = @import("../root.zig");
const memory = r.memory;
const world = r.world;
const entity = r.entity;
const chunks = r.chunks;
const sprite = r.sprite;
const logger = r.logger;

/// Opacity of chunk wireframes.
pub var WIREFRAME_OPACITY: f64 = 0.0;

const CHUNK_SIZE = memory.CHUNK_SIZE;
const CHUNK_SIZE_FLOAT = memory.CHUNK_SIZE_FLOAT;

/// External function that makes a call to `engine.handleVisibleChunks()`.
extern "env" fn jsHandleVisibleChunks(opacity: f64, wireframe_opacity: f64) void;

/// Makes a call to `engine.handleVisibleChunks()` in JS.
pub inline fn handleVisibleChunks(opacity: f64, wireframeOpacity: f64) void {
    if (r.is_wasm) {
        return jsHandleVisibleChunks(opacity, wireframeOpacity);
    } else {
        return; // no native impl yet
    }
}

/// External function that makes a call to `engine.handleVisibleChunks()`.
extern "env" fn jsHandleVisibleEntities() void;

/// Makes a call to `engine.handleVisibleChunks()` in JS.
pub inline fn handleVisibleEntities() void {
    if (r.is_wasm) {
        return jsHandleVisibleEntities();
    } else {
        return; // no native impl yet
    }
}

/// External function that makes a call to `engine.handleVisibleChunks()`.
extern "env" fn jsSetMouseType(mouse_type: r.mouse.MouseType) void;

/// Sets the mouse type of the canvas in JS.
pub inline fn dispatchMouseType() void {
    if (r.is_wasm) {
        jsSetMouseType(r.mouse.mouse_type);
    } else {
        return;
    }
}

/// Processes data for renderFrame() in TypeScript to upload to WebGPU.
pub fn prepareVisibleData(dt: f64, time_diff: f64, canvas_w: f64, canvas_h: f64) void {
    r.chunks.updateVisibleChunks(dt, canvas_w, canvas_h);
    handleVisibleChunks(1.0, WIREFRAME_OPACITY);

    entity.updateEntities(time_diff);

    // no longer using SegmentedList
    // const count = entity.entities.count();

    // const out_ptr: [*]memory.WGSLEntity = @ptrCast(@alignCast(memory.scratchAlloc(count * @sizeOf(memory.WGSLEntity))));
    // const out_slice = out_ptr[0..count];
    // entity.entities.writeToSlice(out_slice, 0);

    handleVisibleEntities();

    // from old SegmentedList code:
    // entity.entities.clearRetainingCapacity(); // clear previous sprites
}
