//! Handles colors, containing ColorRGBA struct and its tests.
const std = @import("std");
const builtin = @import("builtin");

/// Represents a color. Note that WebGPU processes colors as rgba16float;
/// this data is used to determine similarity of blocks and is not color-space compliant.
/// Changed from i8 to u8 because color channels are standard 0-255 unsigned integers.
pub const ColorRGBA = packed struct {
    /// Red component of color (0-255).
    r: u8 = 0,
    /// Green component of color (0-255).
    g: u8 = 0,
    /// Blue component of color (0-255).
    b: u8 = 0,
    /// Alpha component of color (0-255).
    a: u8 = 0,

    pub const white = ColorRGBA{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const black = ColorRGBA{ .r = 0, .g = 0, .b = 0, .a = 255 };

    /// Returns (R+G+B) / 3
    pub fn luminance(self: ColorRGBA) u8 {
        // Scaled weights (approximate to fit u8/u16 math)
        // 0.2126 * 256 ≈ 54
        // 0.7152 * 256 ≈ 183
        // 0.0722 * 256 ≈ 19
        // Sum is 256
        const r_w: u32 = @as(u32, self.r) * 54;
        const g_w: u32 = @as(u32, self.g) * 183;
        const b_w: u32 = @as(u32, self.b) * 19;

        return @intCast((r_w + g_w + b_w) >> 8);
    }

    /// Interpolates two colors linearly.
    pub inline fn mix(self: ColorRGBA, other: ColorRGBA, t: f32) ColorRGBA {
        // Convert float 0.0-1.0 to a fixed-point 0-256 integer
        const amt: u32 = @intFromFloat(@round(t * 256.0));
        const rev: u32 = 256 - amt;

        // Convert to u32 for bit manipulation
        const c1: u32 = @bitCast(self);
        const c2: u32 = @bitCast(other);

        // Mask and calculate Red and Blue simultaneously
        // (RB takes bits 0-7 and 16-23, leaving gaps for overflow)
        const rb_mask = 0x00FF00FF;
        const rb = (((c1 & rb_mask) * rev + (c2 & rb_mask) * amt) >> 8) & rb_mask;

        // Mask and calculate Green and Alpha simultaneously
        // (GA takes bits 8-15 and 24-31)
        const ga_mask = 0xFF00FF00;
        const ga = ((((c1 >> 8) & rb_mask) * rev + ((c2 >> 8) & rb_mask) * amt)) & ga_mask;

        return @bitCast(rb | ga);
    }

    /// Determines similarity between two colors.
    pub fn get_color_distance(color_1: ColorRGBA, color_2: ColorRGBA) f32 {
        // Cast to floats to satisfy the compiler
        const r1: f32 = @floatFromInt(color_1.r);
        const r2: f32 = @floatFromInt(color_2.r);
        const g1: f32 = @floatFromInt(color_1.g);
        const g2: f32 = @floatFromInt(color_2.g);
        const b1: f32 = @floatFromInt(color_1.b);
        const b2: f32 = @floatFromInt(color_2.b);

        const dist_r = r1 - r2;
        const dist_g = g1 - g2;
        const dist_b = b1 - b2;

        const r_mean = (r1 + r2) / 2.0;

        const weight_r = 2.0 + (r_mean / 256.0);
        const weight_g = 4.0;
        const weight_b = 2.0 + ((255.0 - r_mean) / 256.0);

        return (weight_r * dist_r * dist_r) + (weight_g * dist_g * dist_g) + (weight_b * dist_b * dist_b);
    }

    pub fn eql(self: ColorRGBA, other: ColorRGBA) bool {
        return @as(u32, @bitCast(self)) == @as(u32, @bitCast(other));
    }

    /// Hue in degrees [0, 360). Returns 0 for achromatic colors.
    pub fn hue(self: ColorRGBA) u16 {
        const r: i32 = self.r;
        const g: i32 = self.g;
        const b: i32 = self.b;
        const max_c = @max(r, @max(g, b));
        const min_c = @min(r, @min(g, b));
        const delta = max_c - min_c;
        if (delta == 0) return 0;

        var h: i32 = 0;
        if (max_c == r) {
            h = @mod((g - b) * 60, delta * 360);
            h = @divTrunc(h, delta);
        } else if (max_c == g) {
            h = @divTrunc((b - r) * 60, delta) + 120;
        } else {
            h = @divTrunc((r - g) * 60, delta) + 240;
        }
        if (h < 0) h += 360;
        return @intCast(@as(u32, @bitCast(h)));
    }

    /// Saturation as 0-255 (HSV saturation scaled to byte range).
    pub fn saturation(self: ColorRGBA) u8 {
        const max_c = @max(self.r, @max(self.g, self.b));
        const min_c = @min(self.r, @min(self.g, self.b));
        if (max_c == 0) return 0;
        return @intCast((@as(u16, max_c - min_c) * 255) / @as(u16, max_c));
    }

    /// Value (HSV) — simply the maximum channel.
    pub fn value(self: ColorRGBA) u8 {
        return @max(self.r, @max(self.g, self.b));
    }

    /// Lightness (HSL) — average of max and min channels.
    pub fn lightness(self: ColorRGBA) u8 {
        const max_c = @max(self.r, @max(self.g, self.b));
        const min_c = @min(self.r, @min(self.g, self.b));
        return @intCast((@as(u16, max_c) + min_c) / 2);
    }

    /// Perceived brightness using sRGB-approximate formula.
    /// Faster than luminance(), uses sqrt approximation.
    pub fn brightness(self: ColorRGBA) u8 {
        // sqrt(0.299*R² + 0.587*G² + 0.114*B²), integer approx
        const r2: u32 = @as(u32, self.r) * self.r;
        const g2: u32 = @as(u32, self.g) * self.g;
        const b2: u32 = @as(u32, self.b) * self.b;
        // weights: 77/256 ≈ 0.299, 150/256 ≈ 0.587, 29/256 ≈ 0.114
        const weighted = (r2 * 77 + g2 * 150 + b2 * 29) >> 8;
        return @intCast(std.math.sqrt(weighted));
    }

    /// Is fully opaque?
    pub fn isOpaque(self: ColorRGBA) bool {
        return self.a == 255;
    }

    /// Is fully transparent?
    pub fn isTransparent(self: ColorRGBA) bool {
        return self.a == 0;
    }

    /// Invert RGB, keep alpha.
    pub fn invert(self: ColorRGBA) ColorRGBA {
        return .{ .r = 255 - self.r, .g = 255 - self.g, .b = 255 - self.b, .a = self.a };
    }

    /// Convert to grayscale using luminance, keep alpha.
    pub fn toGrayscale(self: ColorRGBA) ColorRGBA {
        const l = self.luminance();
        return .{ .r = l, .g = l, .b = l, .a = self.a };
    }

    /// Alpha-composite `src` over `self` (Porter-Duff "over" operator).
    pub fn compositeOver(self: ColorRGBA, src: ColorRGBA) ColorRGBA {
        const sa: u16 = src.a;
        const da: u16 = self.a;
        const inv_sa: u16 = 255 - sa;

        const out_a = sa + ((da * inv_sa) >> 8);
        if (out_a == 0) return .{};

        return .{
            .r = @intCast((@as(u16, src.r) * sa + @as(u16, self.r) * da * inv_sa / 255) / out_a),
            .g = @intCast((@as(u16, src.g) * sa + @as(u16, self.g) * da * inv_sa / 255) / out_a),
            .b = @intCast((@as(u16, src.b) * sa + @as(u16, self.b) * da * inv_sa / 255) / out_a),
            .a = @intCast(out_a),
        };
    }

    /// Return color with modified alpha.
    pub fn withAlpha(self: ColorRGBA, a: u8) ColorRGBA {
        return .{ .r = self.r, .g = self.g, .b = self.b, .a = a };
    }

    /// Simple average of two colors (no alpha weighting).
    pub fn average(self: ColorRGBA, other: ColorRGBA) ColorRGBA {
        return .{
            .r = @intCast((@as(u16, self.r) + other.r) >> 1),
            .g = @intCast((@as(u16, self.g) + other.g) >> 1),
            .b = @intCast((@as(u16, self.b) + other.b) >> 1),
            .a = @intCast((@as(u16, self.a) + other.a) >> 1),
        };
    }

    /// Converts a comptime hex code into a ColorRGBA (as #ffffff or #ffffffff)
    pub fn fromHex(comptime html_hex: []const u8) ColorRGBA {
        const hex = if (html_hex[0] == '#') html_hex[1..] else html_hex;

        if (hex.len != 6 and hex.len != 8) {
            @compileError("Hex string must be 6 or 8 characters (excluding #)");
        }

        // parse RGB components
        const r = std.fmt.parseInt(u8, hex[0..2], 16) catch unreachable;
        const g = std.fmt.parseInt(u8, hex[2..4], 16) catch unreachable;
        const b = std.fmt.parseInt(u8, hex[4..6], 16) catch unreachable;

        const a = if (hex.len == 8) // parse alpha
            std.fmt.parseInt(u8, hex[6..8], 16) catch unreachable
        else
            255;

        return .{ .r = r, .g = g, .b = b, .a = a };
    }
};

test "ColorRGBA perceptual luminance" {
    const pure_green = ColorRGBA{ .r = 0, .g = 255, .b = 0, .a = 255 };
    const pure_blue = ColorRGBA{ .r = 0, .g = 0, .b = 255, .a = 255 };

    const lum_g = pure_green.luminance();
    const lum_b = pure_blue.luminance();

    try std.testing.expect(lum_g > lum_b * 9);
}

test "ColorRGBA luminance calculation" {
    const grey = ColorRGBA{ .r = 100, .g = 100, .b = 100, .a = 255 };
    try std.testing.expectEqual(@as(u8, 100), grey.luminance());

    const black = ColorRGBA.black;
    try std.testing.expectEqual(@as(u8, 0), black.luminance());

    const custom = ColorRGBA{ .r = 10, .g = 20, .b = 30, .a = 255 };
    try std.testing.expectEqual(@as(u8, 18), custom.luminance());
}

test "ColorRGBA mix interpolation" {
    const red = ColorRGBA{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const blue = ColorRGBA{ .r = 0, .g = 0, .b = 255, .a = 255 };

    const start = red.mix(blue, 0.0);
    try std.testing.expectEqual(red.r, start.r);
    try std.testing.expectEqual(red.b, start.b);

    const end = red.mix(blue, 1.0);
    try std.testing.expectEqual(blue.r, end.r);
    try std.testing.expectEqual(blue.b, end.b);

    const mid = red.mix(blue, 0.5);
    try std.testing.expect(mid.r >= 127 and mid.r <= 128);
    try std.testing.expect(mid.b >= 127 and mid.b <= 128);
    try std.testing.expectEqual(@as(u8, 0), mid.g);
}

test "ColorRGBA color distance" {
    const c1 = ColorRGBA{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const c2 = ColorRGBA{ .r = 255, .g = 0, .b = 0, .a = 255 };
    // Distance to self should ALWAYS be 0
    try std.testing.expectApproxEqAbs(0.0, ColorRGBA.get_color_distance(c1, c2), 0.001);
    const c3 = ColorRGBA{ .r = 0, .g = 0, .b = 0, .a = 255 };
    const dist = ColorRGBA.get_color_distance(c1, c3);

    // Distance should be quite large here
    try std.testing.expect(dist > 100000.0 and dist < 1000000.0);
}

test "ColorRGBA packed layout integrity" {
    // Ensure bitCast works as expected for your mix function logic
    const color = ColorRGBA{ .r = 0xAA, .g = 0xBB, .b = 0xCC, .a = 0xDD };
    const as_u32: u32 = @bitCast(color);

    if (builtin.cpu.arch.endian() == .little) {
        try std.testing.expectEqual(@as(u32, 0xDDCCBBAA), as_u32);
    } else {
        // Expect little-endian.
        unreachable;
    }
}
