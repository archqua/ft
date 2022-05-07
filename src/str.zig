const std = @import("std");

test "" {
    std.debug.print("{}\n", .{@typeInfo([]const u8)});
}
