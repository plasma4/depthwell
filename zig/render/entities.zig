/// Handles entities and stores functions relating on how to add them.
const std = @import("std");
const root = @import("root").root;
const SegmentedList = root.SegmentedList;
const memory = root.memory;
const Entity = memory.Entity;

/// Current number of entities.
pub var count: u64 = 0;
/// Array of entities. TODO determine if this is in stack or safe as-is
pub var entities: SegmentedList(u64, 0) = .{};

/// Draws an unsigned number.
pub fn draw_number(number: u64, position: @Vector(2, f32), lcha: @Vector(4, f32), font_size: f32) void {
    while (number > 0) {
        add_entity(.{
            .position = position,
            .color = lcha,
            .size = font_size,
        });
        number /= 10;
    }
}
/// Draws an integer as text.
pub fn draw_float() void {}
pub fn add_entity(entity: Entity) void {
    entities.append(root.world.arena, entity);
}
