const std = @import("std");
const root = @import("root").root;
const memory = root.memory;
const world = root.world;
const entity = root.entity;
const chunks = root.chunks;
const sprite = root.sprite;
const logger = root.logger;

const SPAN = memory.SPAN;
const SPAN_FLOAT = memory.SPAN_FLOAT;

/// External function that makes a call to `engine.handleVisibleChunks()`.
extern "env" fn js_handle_visible_chunks(opacity: f64) void;

/// Makes a call to `engine.handleVisibleChunks()` in JS.
pub inline fn handle_visible_chunks(opacity: f64) void {
    if (root.is_wasm) {
        return js_handle_visible_chunks(opacity);
    } else {
        return; // no native impl yet
    }
}

/// External function that makes a call to `engine.handleVisibleChunks()`.
extern "env" fn js_handle_visible_entities() void;

/// Makes a call to `engine.handleVisibleChunks()` in JS.
pub inline fn handle_visible_entities() void {
    if (root.is_wasm) {
        return js_handle_visible_entities();
    } else {
        return; // no native impl yet
    }
}

/// Processes data for renderFrame in TypeScript.
pub fn prepare_visible_data(dt: f64, time_diff: f64, canvas_w: f64, canvas_h: f64) void {
    root.chunks.update_visible_chunks(dt, canvas_w, canvas_h);
    handle_visible_chunks(1.0);

    memory.scratch_reset();
    entity.update_entities(time_diff);
    // no longer using SegmentedList
    // const count = entity.entities.count();

    // const out_ptr: [*]memory.WGSLEntity = @ptrCast(@alignCast(memory.scratch_alloc(count * @sizeOf(memory.WGSLEntity))));
    // const out_slice = out_ptr[0..count];
    // entity.entities.writeToSlice(out_slice, 0);

    handle_visible_entities();

    // entity.entities.clearRetainingCapacity(); // clear previous sprites
}
