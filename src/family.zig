const std = @import("std");
const json = std.json;
const person_module = @import("person.zig");
const date_module = @import("date.zig");
const notes_module = @import("notes.zig");
const logger = std.log.scoped(.ft);

const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const Date = date_module.Date;
const Person = person_module.Person;


pub const Family = struct {
    id: Id,
    father_id: ?Person.Id = null,
    mother_id: ?Person.Id = null,
    marriage_date: ?Date = null,
    divorce_date: ?Date = null,
    // these are not necessarily by-blood
    children_ids: ArrayListUnmanaged(Person.Id) = .{},

    pub const Id = i64;
    pub const FromJsonError = error {
        bad_type, bad_field, bad_field_val,
        allocator_required,
    };

    pub fn deinit(this: *Family, ator: Allocator) void {
        this.children_ids.deinit(ator);
    }
    pub fn addChild(this: *Family, child_id: Person.Id, ator: Allocator) !void {
        try this.children_ids.append(ator, child_id);
    }
    pub fn readFromJson(
        this: *Family,
        json_family: json.Value,
        allocator: ?Allocator,
    ) !void {
        switch (json_family) {
            json.Value.Object => |map| {
                inline for (@typeInfo(Family).Struct.fields) |field| {
                    if (map.get(field.name)) |val| {
                        switch (field.field_type) {
                            Id => {
                                switch (val) {
                                    json.Value.Integer => |int| {
                                        this.id = int;
                                    },
                                    else => {
                                        logger.err(
                                            "in Family.readFromJson()" ++
                                            " j_family.get(\"id\")" ++
                                            " is not of type {s}"
                                            , .{"json.Integer"}
                                        );
                                        return FromJsonError.bad_field;
                                    },
                                }
                            },
                            ?Person.Id => {
                                switch (val) {
                                    json.Value.Integer => |int| {
                                        @field(this, field.name) = int;
                                    },
                                    json.Value.Null => {
                                        @field(this, field.name) = null;
                                    },
                                    else => {
                                        logger.err(
                                            "in Family.readFromJson()" ++
                                            " j_family.get(\"{s}\")" ++
                                            " is of neither type {s} nor {s}"
                                            , .{field.name, "json.Integer", "json.Null"}
                                        );
                                        return FromJsonError.bad_field;
                                    },
                                }
                            },
                            ?Date => {
                                var field_ptr = &@field(this, field.name);
                                if (null == field_ptr.*) {
                                    field_ptr.* = .{};
                                    errdefer field_ptr.* = null;
                                    try field_ptr.*.?.readFromJson(val);
                                }
                            },
                            ArrayListUnmanaged(Person.Id) => {
                                if (allocator) |ator| {
                                    switch (val) {
                                        json.Value.Array => |arr| {
                                            try copyFromJsonArr(
                                                    &this.children_ids,
                                                    arr,
                                                    ator,
                                                );
                                        },
                                        else => {
                                            logger.err(
                                                "in Family.readFromJson()" ++
                                                " j_family.get(\"{s}\")" ++
                                                " is not of type {s}"
                                                , .{field.name, "json.Array"}
                                            );
                                            return FromJsonError.bad_field;
                                        },
                                    }
                                } else {
                                    logger.err(
                                        "in Family.readFromJson() allocator required"
                                        , .{}
                                    );
                                    return FromJsonError.allocator_required;
                                }
                            },
                            else => {
                                @compileError("Family.readFromJson() nonexhaustive switch on field_type");
                            },
                        }
                    }
                }
            },
            else => {
                logger.err(
                    "in Family.readFromJson() j_family is not of type {s}"
                    , .{"json.ObjectMap"}
                );
                return FromJsonError.bad_type;
            },
        }
    }
    fn copyFromJsonArr(
        dest: *ArrayListUnmanaged(Person.Id),
        source: json.Array,
        ator: Allocator,
    ) !void {
        var last_read_id: ?Person.Id = null;
        try dest.ensureUnusedCapacity(ator, source.items.len);
        errdefer dest.shrinkAndFree(ator, dest.items.len);
        for (source.items) |item| {
            switch (item) {
                json.Value.Integer => |int| {
                    dest.appendAssumeCapacity(int);
                    last_read_id = int;
                },
                else => {
                    if (last_read_id) |lri| {
                        logger.err(
                            "in Family.readFromJson() (children_ids)" ++
                            " last successfully read id is {d}"
                            , .{lri}
                        );
                    } else {
                        logger.err(
                            "in Family.readFromJson() (children_ids)" ++
                            " no id could be read"
                            , .{}
                        );
                    }
                    return FromJsonError.bad_field_val;
                },
            }
        }
    }
    pub fn readFromJsonSourceStr(
        this: *Family,
        source_str: []const u8,
        ator: Allocator,
    ) !void {
        var parser = json.Parser.init(ator, false); // strings are copied in readFromJson
        defer parser.deinit();
        var tree = try parser.parse(source_str);
        defer tree.deinit();
        try this.readFromJson(tree.root, ator);
    }

    pub const ParentEnum = enum {
        father, mother,
        pub fn asText(comptime self: ParentEnum) switch (self) {
            .father => @TypeOf("father"),
            .mother => @TypeOf("mother"),
        } {
            return switch (self) {
                .father => "father",
                .mother => "mother",
            };
        }
    };
};


const testing = std.testing;
const tator = testing.allocator;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectError = testing.expectError;

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
\\  "notes": ""
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
\\  "notes": ""
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
\\  "notes": ""
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
\\  "notes": ""
\\}
;
const family_source =
\\{
\\  "id": 0,
\\  "father_id": 1,
\\  "mother_id": 2,
\\  "children_ids": [3, 4],
\\  "marriage_date": {"day": null, "month": 1, "year": 2018}
\\}
;

test "basic" {
    {
        var father = Person{.id=-1};
        try father.readFromJsonSourceStr(father_source, tator, .copy);
        defer father.deinit(testing.allocator);
        var mother = Person{.id=-1};
        try mother.readFromJsonSourceStr(mother_source, tator, .copy);
        defer mother.deinit(testing.allocator);
        var family = Family{.id=undefined};
        defer family.deinit(tator);
        try family.readFromJsonSourceStr(family_source, tator);
        try expectEqual(family.marriage_date.?.day, null);
        try expectEqual(family.marriage_date.?.month, 1);
        try expectEqual(family.marriage_date.?.year, 2018);
        try expectEqual(family.divorce_date, null);
        try expectEqual(family.father_id, 1);
        try expectEqual(family.mother_id, 2);
        try expectEqual(family.children_ids.items.len, 2);
        try expectEqual(family.children_ids.items[0], 3);
        try expectEqual(family.children_ids.items[1], 4);
    }
}

fn testError(src: []const u8, expected_error: anyerror) !void {
    var fam = Family{.id=undefined};
    defer fam.deinit(tator);
    try expectError(expected_error, fam.readFromJsonSourceStr(src, tator));
}
const bad_type_src =
\\"family"
;
const bad_field_src_id =
\\{
\\  "id": "family"
\\}
;
const bad_field_src_father_id =
\\{
\\  "father_id": "father"
\\}
;
const bad_field_src_mother_id =
\\{
\\  "mother_id": "mother"
\\}
;
const bad_field_src_children_ids =
\\{
\\  "children_ids": true
\\}
;
const bad_field_sources = [_][]const u8{
    bad_field_src_id,
    bad_field_src_father_id,
    bad_field_src_mother_id,
    bad_field_src_children_ids,
};
const bad_field_val_src =
\\{
\\  "children_ids": [3, 4, "kid"]
\\}
;
fn testAllocatorRequired(src: []const u8) !void {
    var parser = json.Parser.init(tator, false); // strings are copied in readFromJson
    defer parser.deinit();
    var tree = try parser.parse(src);
    defer tree.deinit();
    var fam = Family{.id=undefined};
    defer fam.deinit(tator);
    try expectError(anyerror.allocator_required, fam.readFromJson(tree.root, null));
}
test "errors" {
    try testError(bad_type_src, anyerror.bad_type);
    for (bad_field_sources) |bf_src| {
        try testError(bf_src, anyerror.bad_field);
    }
    try testError(bad_field_val_src, anyerror.bad_field_val);
    try testAllocatorRequired(bad_field_val_src);
}

test "add child" {
    {
        var father = Person{.id=undefined};
        try father.readFromJsonSourceStr(father_source, tator, .copy);
        defer father.deinit(testing.allocator);
        var mother = Person{.id=undefined};
        try mother.readFromJsonSourceStr(mother_source, tator, .copy);
        defer mother.deinit(testing.allocator);
        var family = Family{
            .id = undefined,
            .father_id = father.id,
            .mother_id = mother.id,
        };
        defer family.deinit(tator);
        var son = Person{.id=undefined};
        try son.readFromJsonSourceStr(son_source, tator, .copy);
        defer son.deinit(tator);
        var daughter = Person{.id=undefined};
        try daughter.readFromJsonSourceStr(daughter_source, tator, .copy);
        defer daughter.deinit(tator);
        try family.addChild(son.id, tator);
        try family.addChild(daughter.id, tator);
        try expectEqual(family.children_ids.items[0], 3);
        try expectEqual(family.children_ids.items[1], 4);
    }
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

