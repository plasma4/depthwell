//! Contains sound effect logic and dispatches them to JavaScript.
const std = @import("std");
const root = @import("../root.zig");

/// Random seed used for sound effects. This seed in `startup.init()`.
pub var seed: root.seeding.ChaCha12 = undefined; // interestingly, ChaCha12 silently continues on with undefined init

/// External function that plays a sound (with pitch and volume variation factors).
extern "env" fn jsPlaySound(soundId: u32, volume: f64, pitch: f64) void;

/// Tells JavaScript to play a sound.
/// Use volume and pitch arguments to control a random percentage-based variation.
pub fn playSound(id: u32, base_volume: f64, volume_variation: f64, pitch_variation: f64) void {
    if (root.is_wasm) {
        jsPlaySound(
            id,
            @max(base_volume + generateVariation(volume_variation), 0.1),
            1.0 + generateVariation(pitch_variation),
        );
    } else {
        return;
    }
}

/// Generates a number from -mult to mult using `seed`.
pub fn generateVariation(mult: f64) f64 {
    return @as(f64, @floatFromInt(seed.next())) * (std.math.pow(f64, 2, -63) * mult);
}
