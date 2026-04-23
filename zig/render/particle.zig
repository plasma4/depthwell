//! Handles particle storage for the game. Particles are technically entities.
const std = @import("std");
const root = @import("root").root;
const memory = root.memory;
const Particle = memory.Particle;

/// Custom circular buffer system for particles that doesn't require CPU-side culling.
pub const ParticleSystem = struct {
    list: std.MultiArrayList(Particle) = .{},
    max_particles: usize,

    pub fn init(allocator: std.mem.Allocator, max: usize) !ParticleSystem {
        var sys = ParticleSystem{ .max_particles = max };
        try sys.list.ensureTotalCapacity(allocator, max);
        return sys;
    }

    pub fn spawn(self: *@This(), particle: Particle) void {
        if (self.list.len < self.max_particles) {
            self.list.appendAssumeCapacity(particle);
        }
    }

    /// Updates physics and culls dead particles using Swap-and-Pop
    pub fn update_and_cull(self: *@This(), dt: f32) void {
        const times = self.list.items(.time);
        const positions = self.list.items(.position);
        const d_positions = self.list.items(.d_position);
        const rotations = self.list.items(.rotation);
        const d_rotations = self.list.items(.d_rotation);

        var i: usize = 0;
        while (i < self.list.len) {
            times[i] -= @intFromFloat(dt * 1000.0);

            if (times[i] <= 0) {
                // Dead: Swap with the last element and pop.
                self.list.swapRemove(i);
            } else {
                // Alive: Update physics
                const dt_splat: memory.v2f32 = @splat(dt);
                positions[i] += d_positions[i] * dt_splat;
                rotations[i] += d_rotations[i] * dt;

                i += 1;
            }
        }
    }

    /// Packs the active particles directly into the scratch buffer as WGSLEntities.
    pub fn export_to_scratch_as_entities(self: *@This()) void {
        const count = self.list.len;
        if (count == 0) return;

        // Allocate the exact slice size needed in the scratch buffer
        const slice = memory.scratch_alloc_slice(memory.WGSLEntity, count) orelse return;

        const times = self.list.items(.time);
        const times_end = self.list.items(.time_end);
        const positions = self.list.items(.position);
        const colors = self.list.items(.color);
        const sizes = self.list.items(.size);
        const rotations = self.list.items(.rotation);

        for (0..count) |i| {
            // Optional: Calculate alpha fade based on life remaining
            const life_ratio: f32 = @floatCast(times[i] / times_end[i]);

            slice[i] = .{
                .lcha = .{ colors[i].r, colors[i].g, colors[i].b, colors[i].a * life_ratio },
                .position = positions[i] / .{ root.SCREEN_WIDTH, root.SCREEN_HEIGHT },
                .size = @splat(sizes[i] / root.SCREEN_WIDTH),
                .rotation = rotations[i],
                .id = @intFromEnum(root.Sprite.particle),
            };
        }
    }
};
