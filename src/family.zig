const std = @import("std");
const json = std.json;
const person_module = @import("person.zig");
const date_module = @import("date.zig");
const notes_module = @import("notes.zig");
const util = @import("util.zig");
const logger = std.log.scoped(.ft);

const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Allocator = std.mem.Allocator;
const Date = date_module.Date;
const Person = person_module.Person;


pub const Family = struct {
    id: Id,
    // families are meant to be purely social,
    // family trees handle blood connections
    father_id: ?Person.Id = null,
    mother_id: ?Person.Id = null,
    marriage_date: ?Date = null,
    divorce_date: ?Date = null,
    children_ids: ChildrenIds = .{},

    pub const Id = i64;
    pub const FromJsonError = error {
        bad_type, bad_field, bad_field_val,
        allocator_required,
    };

    pub fn deinit(this: *Family, ator: Allocator) void {
        this.children_ids.deinit(ator);
    }
    pub fn addChild(this: *Family, child_id: Person.Id, ator: Allocator) !void {
        try this.children_ids.addChild(child_id, ator);
    }
    pub fn hasChild(self: Family, candidate: Person.Id) bool {
        return self.children_ids.hasChild(candidate);
        // for (self.children_ids.items) |child_id| {
        //     if (child_id == candidate)
        //         return true;
        // }
        // return false;
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
                                switch (val) {
                                    .Null => {
                                        @field(this, field.name) = null;
                                    },
                                    else => {
                                        var field_ptr = &@field(this, field.name);
                                        if (null == field_ptr.*) {
                                            field_ptr.* = .{};
                                            errdefer field_ptr.* = null;
                                            try field_ptr.*.?.readFromJson(val);
                                        } else {
                                            try field_ptr.*.?.readFromJson(val);
                                        }
                                    },
                                }
                            },
                            ChildrenIds => {
                                try @field(this, field.name).readFromJson(val, allocator);
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
    // pub fn toJson(self: Family, ator: Allocator) json.ObjectMap {
    //     var res = json.ObjectMap.init(ator);
    //     errdefer res.deinit();
    //     inline for (@typeInfo(Family).Struct.fields) |field| {
    //         res.put(
    //             field.name,
    //             if (@hasDecl(@TypeOf(@field(self, field.name)), "toJson")) {
    //                 @field(self, field.name).toJson();
    //             } else {
    //                 @field(self, field.name);
    //             }
    //         );
    //     }
    //     return res;
    // }

    pub fn toJson(
        self: Family,
        ator: Allocator,
        comptime settings: util.ToJsonSettings,
    ) util.ToJsonError!util.ToJsonResult {
        return util.toJson(
            self, ator,
            .{.allow_overload=false, .apply_arena=settings.apply_arena},
        );
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

pub const ChildrenIds = struct {
    data: ArrayListUnmanaged(Person.Id) = .{},

    pub const FromJsonError = error {
        bad_field, bad_field_val, allocator_required,
    };
    pub fn readFromJson(
        this: *ChildrenIds,
        json_children: json.Value,
        allocator: ?Allocator,
    ) !void {
        switch (json_children) {
            json.Value.Array => |arr| {
                if (arr.items.len > 0) {
                    if (allocator) |ator| {
                        try copyFromJsonArr(
                                &this.data,
                                arr,
                                ator,
                            );
                    } else {
                        logger.err(
                            "in Family.readFromJson() allocator required"
                            , .{}
                        );
                        return FromJsonError.allocator_required;
                    }
                } else {
                    return;
                }
            },
            else => {
                logger.err(
                    "in Family.readFromJson()" ++
                    " j_family.get(\"{s}\")" ++
                    " is not of type {s}"
                    , .{"children_ids", "json.Array"}
                );
                return FromJsonError.bad_field;
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

    pub fn toJson(
        self: ChildrenIds,
        ator: Allocator,
        comptime settings: util.ToJsonSettings,
    ) util.ToJsonError!util.ToJsonResult {
        return util.toJson(self.data.items, ator, settings);
    }

    pub fn deinit(this: *ChildrenIds, ator: Allocator) void {
        this.data.deinit(ator);
    }
    pub fn addChild(this: *ChildrenIds, child_id: Person.Id, ator: Allocator) !void {
        try this.data.append(ator, child_id);
    }
    pub fn hasChild(self: ChildrenIds, candidate: Person.Id) bool {
        for (self.data.items) |child_id| {
            if (child_id == candidate)
                return true;
        }
        return false;
    }

    // pub fn equal(
    //     self: ChildrenIds,
    //     other: ChildrenIds,
    //     comptime settings: util.EqualSettings,
    // ) bool {
    //     if (self.data.count() != other.data.count()) {
    //         return false;
    //     }
    //     for (self.data)
    // }
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
        try expectEqual(family.children_ids.data.items.len, 2);
        try expectEqual(family.children_ids.data.items[0], 3);
        try expectEqual(family.children_ids.data.items[1], 4);
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
        try expect(!family.hasChild(3));
        try expect(!family.hasChild(4));
        try family.addChild(son.id, tator);
        try family.addChild(daughter.id, tator);
        try expectEqual(family.children_ids.data.items[0], 3);
        try expectEqual(family.children_ids.data.items[1], 4);
        try expect(family.hasChild(3));
        try expect(family.hasChild(4));
    }
}

test "to json" {
    var family = Family{.id = undefined};
    defer family.deinit(tator);
    try family.readFromJsonSourceStr(family_source, tator);
    var j_family = try family.toJson(tator, .{});
    defer j_family.deinit();
    var ylimaf = Family{.id = undefined};
    defer ylimaf.deinit(tator);
    try ylimaf.readFromJson(j_family.value, tator);
    try expect(util.equal(family, ylimaf, .{}));
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

