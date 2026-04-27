//! Geometric primitives for hit-testing UI and world elements.
const std = @import("std");
const root = @import("root").root;
const memory = root.memory;

const v2f64 = memory.v2f64;

/// An axis-aligned shape; assumed to be in internal viewport coordinates, not UV.
///
/// Behaviour is determined by `r`:
/// - If zero, then it produces an axis-aligned rectangle.
/// - If `r` >= 0.5 and `w` == `h`, then a circle is produced. Functionally identical to a rounded rectangle.
/// - Otherwise, it produces a rounded rectangle.
pub const Shape = struct {
    /// Top-left X and Y coordinate of the shape.
    start: v2f64,
    /// Width of the shape.
    w: f64,
    /// Height of the shape.
    h: f64,
    /// Corner radius (0-0.5+).
    r: f64 = 0.0,

    /// Returns true if the point is inside this shape.
    pub fn contains(self: Shape, point: v2f64) bool {
        // Quick AABB
        if (point[0] < self.start[0] or point[0] > self.start[0] + self.w or
            point[1] < self.start[1] or point[1] > self.start[1] + self.h) return false;

        // Rectangle already confirmed inside AABB
        if (self.r <= 0.0) return true;

        // Circle case: r >= 0.5 and the width equals the height
        if (self.r >= 0.5 and self.w == self.h) {
            const cx = self.start[0] + self.w * 0.5;
            const cy = self.start[1] + self.h * 0.5;
            const rad = self.w * 0.5;
            const dx = point[0] - cx;
            const dy = point[1] - cy;
            return dx * dx + dy * dy <= rad * rad;
        }

        // Rounded rectangle: clamp radius so it never exceeds half the shorter side
        const cr = @min(self.r, 0.5) * @min(self.w, self.h);
        const left = self.start[0] + cr;
        const right = self.start[0] + self.w - cr;
        const top = self.start[1] + cr;
        const bottom = self.start[1] + self.h - cr;

        // Inside the centre cross, so definitely inside
        if (point[0] >= left and point[0] <= right) return true;
        if (point[1] >= top and point[1] <= bottom) return true;

        // Must be in a corner region! Check distance from nearest corner center.
        const cx = if (point[0] < left) left else right;
        const cy = if (point[1] < top) top else bottom;
        const dx = point[0] - cx;
        const dy = point[1] - cy;
        return dx * dx + dy * dy <= cr * cr;
    }

    /// Circle shape constructor.
    pub inline fn circle(center_point: v2f64, radius: f64) Shape {
        return .{
            .start = center_point - @as(v2f64, @splat(radius)),
            .w = radius * 2.0,
            .h = radius * 2.0,
            .r = 0.5,
        };
    }

    /// Rectangle shape constructor (from a top-left position and uniform side length).
    pub inline fn square(point: v2f64, side: f64) Shape {
        return .{
            .start = point,
            .w = side,
            .h = side,
            .r = 0.0,
        };
    }

    /// Rounded rectangle shape constructor (from a top-left position and uniform side length).
    pub inline fn round_square(point: v2f64, side: f64, radius: comptime_float) Shape {
        return .{
            .start = point,
            .w = side,
            .h = side,
            .r = radius,
        };
    }
};
