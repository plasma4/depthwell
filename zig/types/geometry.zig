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
    pub inline fn roundSquare(point: v2f64, side: f64, radius: comptime_float) Shape {
        return .{
            .start = point,
            .w = side,
            .h = side,
            .r = radius,
        };
    }

    /// Returns true if the point is inside this shape.
    pub fn contains(self: Shape, point: v2f64) bool {
        // Quick AABB check
        if (point[0] < self.start[0] or point[0] > self.start[0] + self.w or
            point[1] < self.start[1] or point[1] > self.start[1] + self.h) return false;

        if (self.r <= 0.0) return true;

        // Map point to the first quadrant relative to the shape center
        const half_w = self.w * 0.5;
        const half_h = self.h * 0.5;
        const center = self.start + v2f64{ half_w, half_h };

        // Get absolute distance from center
        const dx = @abs(point[0] - center[0]);
        const dy = @abs(point[1] - center[1]);

        // Rounded rectangle math (uses signed dist fields)
        const cr = @min(self.r, 0.5) * @min(self.w, self.h);

        // Find the vector from the inner rectangle corner to the point
        const qx = dx - (half_w - cr);
        const qy = dy - (half_h - cr);

        // If both qx and qy are positive, we are in the corner region
        if (qx > 0.0 and qy > 0.0) {
            return (qx * qx + qy * qy) <= (cr * cr);
        }

        // In the center cross, pass!
        return true;
    }

    /// Returns true if this shape intersects with another shape.
    pub fn intersecting(self: Shape, other: Shape) bool {
        // Quick AABB check
        if (self.start[0] > other.start[0] + other.w or
            other.start[0] > self.start[0] + self.w or
            self.start[1] > other.start[1] + other.h or
            other.start[1] > self.start[1] + self.h) return false;

        // Calculate absolute corner radius
        const r1 = if (self.r <= 0.0) 0.0 else @min(self.r, 0.5) * @min(self.w, self.h);
        const r2 = if (other.r <= 0.0) 0.0 else @min(other.r, 0.5) * @min(other.w, other.h);

        // Not rounded rectangle/circle: exit early!
        if (r1 == 0.0 and r2 == 0.0) return true;

        // Identify the inner rectangles (the rects formed by the centers of the corner arcs).
        const inner1_min = self.start + @as(v2f64, @splat(r1));
        const inner1_max = self.start + v2f64{ self.w - r1, self.h - r1 };

        const inner2_min = other.start + @as(v2f64, @splat(r2));
        const inner2_max = other.start + v2f64{ other.w - r2, other.h - r2 };

        // Find the distance between these two inner rectangles.
        // We calculate the 1D distance on each axis.
        const dx = @max(0.0, @max(inner1_min[0] - inner2_max[0], inner2_min[0] - inner1_max[0]));
        const dy = @max(0.0, @max(inner1_min[1] - inner2_max[1], inner2_min[1] - inner1_max[1]));

        // If the distance between the inner rects is less than the sum of radii, they hit!
        const dist_sq = dx * dx + dy * dy;
        const radius_sum = r1 + r2;

        return dist_sq <= (radius_sum * radius_sum);
    }
};
