//! Contains sound effect logic and dispatches them to JavaScript.
const std = @import("std");
const root = @import("../root.zig");

/// External function that plays a sound (with pitch and volume variation factors).
extern "env" fn jsPlaySound(soundId: u32, base_volume: f64, volume_variation: f64, pitch_variation: f64) void;

/// Tells JavaScript to play a sound.
/// Use volume and pitch arguments to control a random percentage variation (uses JS-side `Math.random()`).
pub fn playSound(id: u32, base_volume: f64, volume_variation: f64, pitch_variation: f64) void {
    if (root.is_wasm) {
        jsPlaySound(id, base_volume, volume_variation, pitch_variation);
    } else {
        return;
    }
}
