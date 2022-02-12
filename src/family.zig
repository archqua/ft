const person = @import("person.zig");
const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const expect = testing.expect;

pub const Family = struct {
    id: Id,
    father: ?*person.Person,
    mother: ?*person.Person,
    children: ArrayList(*person.Person),

    pub const Id = u64;

    pub const Initializer = struct {
        id: Id,
        father: ?*person.Person,
        mother: ?*person.Person,
    };
    pub fn init(ator: Allocator, initializer: Initializer) Family {
        var children = ArrayList(*person.Person).init(ator);
        var family = Family{
            .id=initializer.id,
            .father=initializer.father,
            .mother=initializer.mother,
            .children = children,
        };
    }
    pub fn deinit(this: *Family) void {
        this.children.deinit();
    }
    pub fn addChild(this: *Family, child: *person.Person) !void {
        try this.children.append(child);
    }
};

test "basic";
test "add child";
