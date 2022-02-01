const std = @import("std");

pub fn main() u8 {
    return 0;
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
