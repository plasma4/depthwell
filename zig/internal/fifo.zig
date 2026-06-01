const std = @import("std");
const Allocator = std.mem.Allocator;

/// An amortized O(1) unbounded first-in, first-out (FIFO) queue implemented
/// as a dynamic circular ring buffer.
pub fn UnboundedFifo(comptime T: type) type {
    return struct {
        const Self = @This();

        buf: []T = &.{},
        head: usize = 0,
        tail: usize = 0,
        count: usize = 0,

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.buf);
            self.* = undefined;
        }

        /// Pushes an item to the back of the FIFO, dynamically growing if full.
        pub fn addOne(self: *Self, item: T, allocator: Allocator) !void {
            if (self.count == self.buf.len) {
                try self.grow(allocator);
            }

            self.buf[self.tail] = item;
            self.tail = (self.tail + 1) % self.buf.len;
            self.count += 1;
        }

        /// Pops an item from the front of the FIFO. Returns null if empty.
        pub fn pop(self: *Self) ?T {
            if (self.count == 0) return null;

            const item = self.buf[self.head];
            self.head = (self.head + 1) % self.buf.len;
            self.count -= 1;

            // Reset indices if empty to keep memory linear
            if (self.count == 0) {
                self.head = 0;
                self.tail = 0;
            }

            return item;
        }

        /// Internal growth algorithm to double capacity and unwrap the ring buffer
        fn grow(self: *Self, allocator: Allocator) !void {
            const old_capacity = self.buf.len;
            const new_capacity = if (old_capacity == 0) 8 else old_capacity * 2;

            // Try to resize the existing buffer in-place
            if (old_capacity > 0 and allocator.resize(self.buf, new_capacity)) {
                self.buf.len = new_capacity;

                // If the data was wrapped around, we have to fix the broken ring
                if (self.tail <= self.head and self.count > 0) {
                    const first_part_len = old_capacity - self.head;
                    // Shift the wrapped elements to the end of the newly expanded buffer
                    std.mem.copyBackwards(T, self.buf[new_capacity - first_part_len .. new_capacity], self.buf[self.head..old_capacity]);
                    self.head = new_capacity - first_part_len;
                }
                return;
            }

            // Instead, just make new memory and copy if in-place resizing fails
            const new_buf = try allocator.alloc(T, new_capacity);

            if (self.count > 0) {
                if (self.head < self.tail) {
                    @memcpy(new_buf[0..self.count], self.buf[self.head..self.tail]);
                } else {
                    const first_part = self.buf[self.head..];
                    const second_part = self.buf[0..self.tail];
                    @memcpy(new_buf[0..first_part.len], first_part);
                    @memcpy(new_buf[first_part.len .. first_part.len + second_part.len], second_part);
                }
            }

            allocator.free(self.buf);
            self.buf = new_buf;
            self.head = 0;
            self.tail = self.count;
        }

        /// Iterates over every active element in the FIFO out-of-order.
        /// Passes a pointer to each item to the provided callback function.
        pub fn forEach(self: *Self, context: anytype, comptime callback: fn (ctx: @TypeOf(context), item: *T) void) void {
            if (self.count == 0) return;

            if (self.head < self.tail) {
                // Data is linear
                for (self.buf[self.head..self.tail]) |*item| {
                    callback(context, item);
                }
            } else {
                // Data is wrapped around the ring
                for (self.buf[self.head..]) |*item| {
                    callback(context, item);
                }
                for (self.buf[0..self.tail]) |*item| {
                    callback(context, item);
                }
            }
        }
    };
}
