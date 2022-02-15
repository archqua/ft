const person = @import("person.zig");
const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const expect = testing.expect;
const json = std.json;

pub const Family = struct {
    id: Id,
    father_id: ?person.Person.Id,
    mother_id: ?person.Person.Id,
    marriage_date: ?person.Date = null,
    divorce_date: ?person.Date = null,
    children_ids: ArrayList(person.Person.Id),

    pub const Id = i64;

    pub const Initializer = struct {
        id: Id,
        father_id: ?person.Person.Id,
        mother_id: ?person.Person.Id,
        marriage_date: ?person.Date = null,
        divorce_date: ?person.Date = null,
    };
    pub fn init(ator: Allocator, initializer: Initializer) Family {
        var family: Family = undefined;
        family.id = initializer.id;
        inline for (@typeInfo(Initializer).Struct.fields) |field| {
            @field(family, field.name) = @field(initializer, field.name);
        }
        family.children_ids = ArrayList(person.Person.Id).init(ator);
        return family;
    }
    pub fn deinit(this: *Family) void {
        this.children_ids.deinit();
    }
    pub fn addChild(this: *Family, child_id: person.Person.Id) !void {
        try this.children_ids.append(child_id);
    }
};


const father_source =
    \\{
    \\  "id": 1,
    \\  "name": {
    \\      "normal_form": "Father",
    \\      "short_form": "Daddy",
    \\      "patronymic_male_form": "Fathersson",
    \\      "patronymic_female_form": "Fathersdaughter"
    \\  },
    \\  "surname": {"male_form": "Ivanov", "female_form": "Ivanova"},
    \\  "patronymic": "Fathersson",
    \\  "sex": "male",
    \\  "birth_date": {"day": 3, "month": 2, "year": 2000},
    \\  "death_date": null,
    \\  "notes": null
    \\}
;
const mother_source =
    \\{
    \\  "id": 2,
    \\  "name": {"normal_form": "Mother", "short_form": "Mommy"},
    \\  "surname": {"male_form": "Petrov", "female_form": "Petrova"},
    \\  "patronymic": "Fathersdaughter",
    \\  "sex": "female",
    \\  "birth_date": {"day": 2, "month": 3, "year": 2000},
    \\  "death_date": null,
    \\  "notes": null
    \\}
;
const son_source =
    \\{
    \\  "id": 3,
    \\  "name": "Son",
    \\  "surname": {"male_form": "Ivanov", "female_form": "Ivanova"},
    \\  "patronymic": "Fathersson",
    \\  "sex": "male",
    \\  "birth_date": {"day": 4, "month": 5, "year": 2020},
    \\  "death_date": null,
    \\  "notes": null
    \\}
;
const daughter_source =
    \\{
    \\  "id": 4,
    \\  "name": "Daughter",
    \\  "surname": {"male_form": "Ivanov", "female_form": "Ivanova"},
    \\  "patronymic": "Fathersdaughter",
    \\  "sex": "female",
    \\  "birth_date": {"day": 4, "month": 5, "year": 2020},
    \\  "death_date": null,
    \\  "notes": null
    \\}
;

test "basic" {
    {
        var father = person.Person{.id=-1};
        try father.initFromJsonSourceStr(father_source, .{.ator=testing.allocator});
        defer father.free(testing.allocator);
        var mother = person.Person{.id=-1};
        try mother.initFromJsonSourceStr(mother_source, .{.ator=testing.allocator});
        defer mother.free(testing.allocator);
        var family = Family.init(
            testing.allocator,
            .{
                .father_id = father.id,
                .mother_id = mother.id,
                .id = 0,
            },
        );
        defer family.deinit();
        try expect(null == family.marriage_date);
        try expect(family.father_id.? == 1);
        try expect(family.mother_id.? == 2);
    }
}
test "add child" {
    var father = person.Person{.id=-1};
    try father.initFromJsonSourceStr(father_source, .{.ator=testing.allocator});
    defer father.free(testing.allocator);
    var mother = person.Person{.id=-1};
    try mother.initFromJsonSourceStr(mother_source, .{.ator=testing.allocator});
    defer mother.free(testing.allocator);
    var family = Family.init(
        testing.allocator,
        .{
            .father_id = father.id,
            .mother_id = mother.id,
            .id = 0,
        },
    );
    defer family.deinit();
    var son = person.Person{.id=-1};
    try son.initFromJsonSourceStr(son_source, .{.ator=testing.allocator});
    defer son.free(testing.allocator);
    var daughter = person.Person{.id=-1};
    try daughter.initFromJsonSourceStr(daughter_source, .{.ator=testing.allocator});
    defer daughter.free(testing.allocator);
    try family.addChild(son.id);
    try family.addChild(daughter.id);
    try expect(family.children_ids.items[0] == 3);
    try expect(family.children_ids.items[1] == 4);
}

fn strCopyAlloc(from: []const u8, ator: Allocator) ![]u8 {
    var res = try ator.alloc(u8, from.len);
    for (from) |c, i| {
        res[i] = c;
    }
    return res;
}

fn strEqual(lhs: []const u8, rhs: []const u8) bool {
    if (lhs.len != rhs.len)
        return false;
    for (lhs) |c, i| {
        if (c != rhs[i])
            return false;
    }
    return true;
}

