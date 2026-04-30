const std = @import("std");
const root = @import("root").root;
const memory = root.memory;
const world = root.world;
const entity = root.entity;
const chunks = root.chunks;
const sprite = root.sprite;
const logger = root.logger;

const CHUNK_SIZE = memory.CHUNK_SIZE;
const CHUNK_SIZE_FLOAT = memory.CHUNK_SIZE_FLOAT;

/// External function that makes a call to `engine.handleVisibleChunks()`.
extern "env" fn jsHandleVisibleChunks(opacity: f64) void;

/// Makes a call to `engine.handleVisibleChunks()` in JS.
pub inline fn handleVisibleChunks(opacity: f64) void {
    if (root.is_wasm) {
        return jsHandleVisibleChunks(opacity);
    } else {
        return; // no native impl yet
    }
}

/// External function that makes a call to `engine.handleVisibleChunks()`.
extern "env" fn jsHandleVisibleEntities() void;

/// Makes a call to `engine.handleVisibleChunks()` in JS.
pub inline fn handleVisibleEntities() void {
    if (root.is_wasm) {
        return jsHandleVisibleEntities();
    } else {
        return; // no native impl yet
    }
}

/// External function that makes a call to `engine.handleVisibleChunks()`.
extern "env" fn jsSetMouseType(mouse_type: root.mouse.MouseType) void;

/// Sets the mouse type of the canvas in JS.
pub inline fn dispatchMouseType() void {
    if (root.is_wasm) {
        jsSetMouseType(root.mouse.mouse_type);
    } else {
        return;
    }
}

/// Processes data for renderFrame in TypeScript.
pub fn prepareVisibleData(dt: f64, time_diff: f64, canvas_w: f64, canvas_h: f64) void {
    root.chunks.updateVisibleChunks(dt, canvas_w, canvas_h);
    handleVisibleChunks(1.0);

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
