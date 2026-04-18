//! Handles block selection from the mouse.
const std = @import("std");
const memory = @import("memory.zig");

pub var mouse_chunk: ?memory.Coordinate = null;
pub var mouse_subpixel: ?memory.v2u64 = null;

/// Handles mouse logic, where `x` and `y` values are between 0-1, acting like a UV over the whole canvas from HTML.
/// Action 0: mousemove (or touch equivalent)
/// Action 1: mousedown (or touch equivalent)
/// Action 2: mouseup   (or touch equivalent)
pub fn handle_mouse(x: f64, y: f64, action: u32) void {
    // use the camera's scale and camera pan to determine what specific Coordinate/subpixel in chunk we are selecting
    mouse_chunk = .{ .suffix = .{ 0, 0 }, .quadrant = 0 };
    _ = .{ x, y, action };
}
