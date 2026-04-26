//! Geometric primitives for hit-testing UI and world elements.
const std = @import("std");

/// A 2D point in screen-pixel space (0–480, 0–270).
pub const Point = struct {
    x: f32,
    y: f32,

    /// Construct from a SIMD vector.
    pub inline fn from_vec(v: @Vector(2, f32)) Point {
        return .{ .x = v[0], .y = v[1] };
    }
};

/// An axis-aligned shape in screen-pixel space.
///
/// Behaviour is determined by `r`.
/// - If zero, then it produces an axis-aligned rectangle.
/// - If >= 50 and `w` == `h`, then a circle is produced. Functionally identical to a rounded rectangle.
/// - Otherwise, it produces a rounded rectangle.
pub const Shape = struct {
    /// Top-left corner X.
    x: f32,
    /// Top-left corner Y.
    y: f32,
    /// Width of the shape.
    w: f32,
    /// Height of the shape.
    h: f32,
    /// Corner radius (0-50+).
    r: f32 = 0.0,

    /// Returns true if `p` is inside this shape.
    pub fn contains(self: Shape, p: Point) bool {
        // Quick AABB
        if (p.x < self.x or p.x > self.x + self.w or
            p.y < self.y or p.y > self.y + self.h) return false;

        // Rectangle already confirmed inside AABB
        if (self.r == 0.0) return true;

        // Circle case: r >= 50 and the shape is square
        if (self.r >= 50.0 and self.w == self.h) {
            const cx = self.x + self.w * 0.5;
            const cy = self.y + self.h * 0.5;
            const rad = self.w * 0.5;
            const dx = p.x - cx;
            const dy = p.y - cy;
            return dx * dx + dy * dy <= rad * rad;
        }

        // Rounded rectangle: clamp radius so it never exceeds half the shorter side
        const cr = @min(self.r, @min(self.w, self.h) * 0.5);
        const left = self.x + cr;
        const right = self.x + self.w - cr;
        const top = self.y + cr;
        const bottom = self.y + self.h - cr;

        // Inside the centre cross, so definitely inside
        if (p.x >= left and p.x <= right) return true;
        if (p.y >= top and p.y <= bottom) return true;

        // Must be in a corner region! Check distance from nearest corner center.
        const cx = if (p.x < left) left else right;
        const cy = if (p.y < top) top else bottom;
        const dx = p.x - cx;
        const dy = p.y - cy;
        return dx * dx + dy * dy <= cr * cr;
    }

    /// Circle shape constructor.
    pub inline fn circle(cx: f32, cy: f32, radius: f32) Shape {
        return .{
            .x = cx - radius,
            .y = cy - radius,
            .w = radius * 2.0,
            .h = radius * 2.0,
            .r = 50.0,
        };
    }

    /// Rectangle shape constructor (from a top-left position and uniform side length).
    pub inline fn square(x: f32, y: f32, side: f32) Shape {
        return .{
            .x = x,
            .y = y,
            .w = side,
            .h = side,
            .r = 0.0,
        };
    }
};
