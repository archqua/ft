const std = @import("std");
const date_module = @import("date.zig");
const Date = date_module.Date;
const notes_module = @import("notes.zig");
const Notes = notes_module.Notes;
const Allocator = std.mem.Allocator;
const json = std.json;
const ArrayList = std.ArrayList;
const testing = std.testing;
const expect = testing.expect;

pub const Person = struct {
    id: Id,
    name: Name,
    alternative_names: NameList,
    surname: Surname,
    alternative_surnames: SurnameList,
    patronymic: Patronymic,
    sex: ?Sex = null,
    birth_date: ?Date = null,
    death_date: ?Date = null,
    notes: Notes,
    ator: Allocator,

    // pub const default_id: Id = -1;
    pub const Id = i64;
    // pub const FromJsonOptions = struct {
    //     ator: ?Allocator = null,
    //     // person_default_id: ?i64 = null,
    // };
    pub fn init(id: Id, ator: Allocator) Person {
        var person: Person = undefined;
        person.id=id;
        person.ator=ator;
        inline for (@typeInfo(Initializer).Struct.fields) |field| {
            switch (field.field_type) {
                Id, Allocator, ?Sex, ?Date => {},
                else => {
                    @field(person, field.name) = field.field_type.init(ator);
                },
            }
        }
    }
    pub fn deinit(this: *Person) void {
        inline for (@typeInfo(Person).Struct.fields) |field| {
            switch (field.field_type) {
                Id, Allocator, ?Sex, ?Date => {},
                else => {
                    @field(this, field.name).deinit();
                },
            }
        }
    }
    pub const FromJsonError = error { bad_type, bad_field, };
    pub fn readFromJson(
        this: *Person,
        json_person: json.Value,
        // options: FromJsonOptions
    ) !void {
        switch (json_person) {
            json.Value.Object => |map| {
                inline for (@typeInfo(Person).Struct.fields) |field| {
                    if (map.get(field.name)) |val| {
                        switch (field.field_type) {
                            Id => {
                                switch (val) {
                                    json.Value.Integer => |int| {
                                        this.id = int;
                                    },
                                    else => { return FromJsonError.bad_field; },
                                }
                            },
                            ?Date, ?Sex => {
                                switch (val) {
                                    json.Value.Null => {
                                        @field(this, field.name) = null,
                                    },
                                    else => {
                                        if (@field(this, field.name) == null)
                                            @field(this, field.name) = .{};
                                        try @field(this, field.name).?.readFromJson(val);
                                    },
                                }
                            },
                            else => {
                                try @field(this, field.name).readFromJson(val);
                            },
                        }
                    }
                }
            },
            else => { return FromJsonError.bad_type; },
        }
    }
    pub fn readFromJsonSourceStr(
        this: *Person,
        source_str: []const u8,
        // comptime options: FromJsonOptions,
    ) !void {
        const ator = this.ator;
        var parser = json.Parser.init(ator, false); // strings are copied in readFromJson
        defer parser.deinit();
        var tree = try parser.parse(source_str);
        defer tree.deinit();
        try this.readFromJson(tree.root, options);
    }
    pub const RenameOptions = struct {
        copy: bool,
    };
    pub const RenameError = error { allocators_mismatch, };
    pub fn rename(
        this: *Person,
        new_name_ptr: anytype,
        options: enum { copy, move, },
    ) !void {
        switch (options) {
            .copy => {
                var copy = try new_name_ptr.copy(this.name.ator);
                defer copy.deinit();
                this.name.swap(&copy);
            },
            .move => {
                if (this.name.ator.vtable != new_name_ptr.ator.vtable)
                    return RenameError.allocators_mismatch;
                this.name.deinit();
                this.name = new_name_ptr.move();
            },
        }
    }
    pub fn setDate(this: *Person, date: Date, which: enum { birth, death, }) !void {
        try date.validate();
        switch (which) {
            .birth => {
                this.birth_date = date;
            },
            .death => {
                this.death_date = date;
            },
        }
    }
};

pub const Name = struct {
    normal_form: []const u8 = "",
    short_form: []const u8 = "",
    full_form: []const u8 = "",
    patronymic_male_form: []const u8 = "",
    patronymic_female_form: []const u8 = "",
    ator: Allocator,

    pub const FromJsonError = error { bad_type, bad_field, };
    pub fn init(ator: Allocator) Name {
        return Name{.ator=ator};
    }
    pub fn deinit(this: *Name) void {
        inline for (@typeInfo(Name).Struct.fields) |field| {
            switch (field.field_type) {
                []const u8 => {
                    this.ator.free(@field(this, field.name));
                },
                else => {},
            }
        }
    }
    pub fn readFromJson(
        this: *Name,
        json_name: json.Value,
        // options: Person.FromJsonOptions,
    ) !void {
        switch (json_name) {
            json.Value.Object => |map| {
                inline for (@typeInfo(Name).Struct.fields) |field| {
                    switch (field.field_type) {
                        []const u8 => {
                            if (map.get(field.name)) |val| {
                                var _field = &@field(this, field.name);
                                switch (val) {
                                    json.Value.String, json.Value.NumberString => |str| {
                                        var slice = try strCopyAlloc(str, this.ator);
                                        this.ator.free(_field.*);
                                        _field.* = slice;
                                    },
                                    json.Value.Null => {
                                        this.ator.free(_field.*);
                                        _field.* = "";
                                    },
                                    else => { return FromJsonError.bad_field; },
                                }
                            }
                        },
                        Allocator => {}, // lmao
                        else => { @compileError("Name nonexhaustive field_type switch"); }
                    }
                }
            },
            json.Value.String => |str| {
                var slice = try strCopyAlloc(str, this.ator);
                this.ator.free(this.normal_form);
                this.normal_form = slice;
            },
            else => { return FromJsonError.bad_type; },
        }
    }
};

pub const NameList = struct {
    data: ArrayList(Name),
    ator: Allocator,

    pub const FromJsonError = error { bad_type, bad_item, };
    pub fn init(ator: Allocator) void {
        return NameList{.ator=ator, .data=ArrayList(Name).init(ator)};
    }
    pub fn deinit(this: *NameList) void {
        for (this.data.items) |*name| {
            name.deinit();
        }
        this.data.deinit();
    }
    pub fn initFromJson(
        this: *NameList,
        json_name_list: json.Value,
        // options: Person.FromJsonOptions,
    ) !void {
        switch (json_name_list) {
            json.Value.Array => |arr| {
                for (arr.items) |item| {
                    switch (item) {
                        json.Value.Object, json.Value.String, json.Value.NumberString => {
                            var name = Name.init(this.ator);
                            errdefer name.deinit();
                            try name.readFromJson(item, options);
                            try this.data.append(this.ator, name);
                        },
                        else => { return FromJsonError.bad_item; },
                    }
                }
            },
            else => { return FromJsonError.bad_type; },
        }
    }
};

// TODO

pub const Surname = struct {
    male_form: []const u8 = "",
    female_form: []const u8 = "",

    pub const FromJsonError = error { bad_type, bad_field, };
    pub fn initFromJson(
        this: *Surname,
        json_surname: json.Value,
        options: Person.FromJsonOptions,
    ) !void {
        switch (json_surname) {
            json.Value.Object => |map| {
                inline for (@typeInfo(Surname).Struct.fields) |field| {
                    if (map.get(field.name)) |val| {
                        switch (val) {
                            json.Value.String, json.Value.NumberString => |str| {
                                var _field = &@field(this, field.name);
                                switch (field.field_type) {
                                    []const u8 => {
                                        if (options.ator) |ator| {
                                            _field.* = try strCopyAlloc(str, ator);
                                        } else {
                                            _field.* = str;
                                        }
                                    },
                                    ?[]const u8 => {
                                        if (_field.* == null)
                                            _field.* = "";
                                        if (options.ator) |ator| {
                                            _field.*.? = try strCopyAlloc(str, ator);
                                        } else {
                                            _field.*.? = str;
                                        }
                                    },
                                    else => {
                                        @compileError("Name nonexhaustive field_type switch");
                                    },
                                }
                            },
                            else => { return FromJsonError.bad_field; },
                        }
                    }
                }
            },
            json.Value.String => |str| {
                if (options.ator) |ator| {
                    this.male_form = try strCopyAlloc(str, ator);
                } else {
                    this.male_form = str;
                }
            },
            else => { return FromJsonError.bad_type; },
        }
    }
    pub fn free(this: *Surname, ator: Allocator) void {
        inline for (@typeInfo(Surname).Struct.fields) |field| {
            switch (field.field_type) {
                []const u8 => {
                    if (@field(this, field.name).len != 0) {
                        // is .len != 0 actually OK?
                        ator.free(@field(this, field.name));
                    }
                },
                ?[] const u8 => {
                    if (@field(this, field.name) != null) {
                        ator.free(@field(this, field.name).?);
                        @field(this, field.name) = null;
                    }
                },
                else => { @compileError("Surname.free() nonexhaustive field_type switch"); }
            }
        }
    }
};

pub const SurnameList = struct {
    // TODO
};

pub const Patronymic = struct {
    data: []const u8 = "",

    pub const FromJsonError = error { bad_type, bad_field, };
    pub fn initFromJson(
        this: *Patronymic,
        json_patronymic: json.Value,
        options: Person.FromJsonOptions,
    ) !void {
        switch (json_patronymic) {
            json.Value.String, json.Value.NumberString => |str| {
                if (options.ator) |ator| {
                    this.data = try strCopyAlloc(str, ator);
                } else {
                    this.data = str;
                }
            },
            else => { return FromJsonError.bad_type; },
        }
    }
    pub fn free(this: *Patronymic, ator: Allocator) void {
        if (this.data.len != 0)
            // is .len != 0 actually OK?
            ator.free(this.data);
    }
};

pub const Sex = struct {
    data: enum(u1) { male = 1, female = 0, } = .male,

    pub const FromJsonError = error { bad_type, bad_field, };
    pub fn initFromJson(
        this: *Sex,
        json_sex: json.Value,
        options: Person.FromJsonOptions,
    ) !void {
        _ = options;
        switch (json_sex) {
            json.Value.String => |str| {
                if (strEqual("male", str)) {
                    this.data = .male;
                } else if (strEqual("female", str)) {
                    this.data = .female;
                } else {
                    return FromJsonError.bad_field;
                }
            },
            json.Value.Bool => |is_male| {
                if (is_male) {
                    this.data = .male;
                } else {
                    this.data = .female;
                }
            },
            json.Value.Integer => |int| {
                if (int == 1) {
                    this.data = .male;
                } else if (int == 0) {
                    this.data = .female;
                } else {
                    return FromJsonError.bad_field;
                }
            },
            else => { return FromJsonError.bad_type; },
        }
    }
    pub fn free(this: *Sex, ator: Allocator) void {
        _ = this; _ = ator;
    }
};

const human_full_source =
    \\{
    \\  "id": 1,
    \\  "name": {"normal_form": "Human", "short_form": "Hum"},
    \\  "surname": {"male_form": "Ivanov", "female_form": "Ivanova"},
    \\  "patronymic": "Fathersson",
    \\  "sex": "male",
    \\  "birth_date": {"day": 3, "month": 2, "year": 2000},
    \\  "death_date": null,
    \\  "notes": null
    \\}
;
const human_short_source =
    \\{
    \\  "id": 2,
    \\  "name": "Human",
    \\  "surname": "Ivanov",
    \\  "patronymic": "Fathersson",
    \\  "sex": "male",
    \\  "birth_date": {"day": 3, "month": 2, "year": 2000},
    \\  "death_date": null,
    \\  "notes": null
    \\}
;
const mysterious_source = 
    \\{
    \\  "id": 3,
    \\  "name": null,
    \\  "surname": null,
    \\  "patronymic": null,
    \\  "sex": null,
    \\  "notes": null
    \\}
;

test "name" {
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(human_full_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try expect(strEqual("Human", human.name.?.normal_form));
        try expect(strEqual("Hum", human.name.?.short_form.?));
        try expect(null == human.name.?.full_form);
    }
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(human_short_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try expect(strEqual("Human", human.name.?.normal_form));
        try expect(null == human.name.?.short_form);
        try expect(null == human.name.?.full_form);
    }
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(mysterious_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try expect(null == human.name);
        human.name = .{.normal_form = try strCopyAlloc("", testing.allocator)};
    }
}

test "surname" {
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(human_full_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try expect(strEqual("Ivanov", human.surname.?.male_form));
        try expect(strEqual("Ivanova", human.surname.?.female_form.?));
    }
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(human_short_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try expect(strEqual("Ivanov", human.surname.?.male_form));
        try expect(null == human.surname.?.female_form);
    }
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(mysterious_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try expect(null == human.surname);
    }
}

test "patronymic" {
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(human_full_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try expect(strEqual("Fathersson", human.patronymic.?.data));
    }
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(human_short_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try expect(strEqual("Fathersson", human.patronymic.?.data));
    }
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(mysterious_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try expect(null == human.patronymic);
    }
}

test "sex" {
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(human_full_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try expect(human.sex.?.data == .male);
    }
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(human_short_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try expect(human.sex.?.data == .male);
    }
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(mysterious_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try expect(null == human.sex);
    }
}

test "date" {
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(human_full_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try expect(human.birth_date.?.day.? == 3);
        try expect(human.birth_date.?.month.? == 2);
        try expect(human.birth_date.?.year.? == 2000);
        try expect(human.death_date == null);
    }
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(human_short_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try expect(human.birth_date.?.day.? == 3);
        try expect(human.birth_date.?.month.? == 2);
        try expect(human.birth_date.?.year.? == 2000);
        try expect(human.death_date == null);
    }
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(mysterious_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try expect(null == human.birth_date);
        try expect(null == human.death_date);
    }
}

test "notes" {
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(human_full_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try expect(null == human.notes);
    }
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(human_short_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try expect(null == human.notes);
    }
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(mysterious_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try expect(null == human.notes);
    }
}

test "rename" {
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(human_full_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try human.rename(
            Name{.normal_form="Osetr"},
            .{.new_ator=testing.allocator, .del_ator=testing.allocator,},
        );
        try expect(strEqual(human.name.?.normal_form, "Osetr"));
    }
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(human_short_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try human.rename(
            Name{.normal_form="Osetr"},
            .{.new_ator=testing.allocator, .del_ator=testing.allocator,},
        );
        try expect(strEqual(human.name.?.normal_form, "Osetr"));
    }
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(mysterious_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try human.rename(
            Name{.normal_form="Osetr"},
            .{.new_ator=testing.allocator, .del_ator=testing.allocator,},
        );
        try expect(strEqual(human.name.?.normal_form, "Osetr"));
    }
}

test "set date" {
    {
        var human = Person{ .id=0, };
        try human.initFromJsonSourceStr(human_full_source, .{.ator=testing.allocator});
        defer human.free(testing.allocator);
        try human.setDate(Date{.day=2, .month=3, .year=2}, .birth);
        try human.setDate(Date{.day=1, .month=1, .year=-1}, .death);
        try expect(human.birth_date.?.day.? == 2);
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

