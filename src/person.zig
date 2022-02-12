const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;
const builtin = std.builtin;
const testing = std.testing;
const expect = testing.expect;

pub const Person = struct {
    id: Id,
    name: ?Name = null,
    surname: ?Surname = null,
    patronymic: ?Patronymic = null,
    sex: ?Sex = null,
    birth_date: ?Date = null,
    death_date: ?Date = null,
    notes: ?Notes = null,
    // events: Events,

    pub const Id = u64;
    pub const FromJsonOptions = struct {
        ator: ?Allocator = null,
    };
    pub const FromJsonError = error { bad_type, bad_field, };
    pub fn initFromJson(
        this: *Person,
        json_person: json.Value,
        options: FromJsonOptions
    ) !void {
        switch (json_person) {
            json.Value.Object => |map| {
                inline for (@typeInfo(Person).Struct.fields) |field| {
                    if (map.get(field.name)) |val| {
                        if (field.field_type == Id) {
                            switch (val) {
                                json.Value.Integer => |int| {
                                    this.id = @bitCast(u64, int);
                                },
                                else => { return FromJsonError.bad_field; },
                            }
                        } else {
                            switch (val) {
                                json.Value.Null => {
                                    @field(this, field.name) = null;
                                },
                                else => {
                                    if (@field(this, field.name) == null)
                                        @field(this, field.name) = .{};
                                    try @field(this, field.name).?.initFromJson(val, options);
                                },
                            }
                        }
                    }
                }
            },
            else => { return FromJsonError.bad_type; },
        }
    }
    pub fn free(this: *Person, ator: Allocator) void {
        inline for (@typeInfo(Person).Struct.fields) |field| {
            if (field.field_type != Id) {
                if (@field(this, field.name) != null) {
                    @field(this, field.name).?.free(ator);
                    @field(this, field.name) = null;
                }
            }
        }
    }
    pub const RenameOptions = struct {
        new_ator: ?Allocator = null,
        del_ator: ?Allocator = null,
    };
    pub fn rename(
        this: *Person,
        new_name: Name,
        options: RenameOptions
    ) !void {
        if (options.del_ator) |ator| {
            if (this.name != null)
                this.name.?.free(ator);
        }
        if (null == this.name)
            this.name = .{};
        if (options.new_ator) |ator| {
            inline for (@typeInfo(Name).Struct.fields) |field| {
                switch (field.field_type) {
                    []const u8 => {
                        @field(this.name.?, field.name) = try strCopyAlloc(@field(new_name, field.name), ator);
                    },
                    ?[]const u8 => {
                        if (@field(new_name, field.name) != null) {
                            @field(this.name.?, field.name) = try strCopyAlloc(@field(new_name, field.name).?, ator);
                        }
                    },
                    else => { @compileLog("Person.rename() nonexhaustive switch on Name field types"); },
                }
            }
        } else {
            inline for (@typeInfo(Name).Struct.fields) |field| {
                @field(this.name.?, field.name) = @field(new_name, field.name);
            }
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
    short_form: ?[]const u8 = null,
    full_form: ?[]const u8 = null,
    patronymic_male_form: ?[]const u8 = null,
    patronymic_female_form: ?[]const u8 = null,

    pub const FromJsonError = error { bad_type, bad_field, };
    pub fn initFromJson(
        this: *Name,
        json_name: json.Value,
        options: Person.FromJsonOptions,
    ) !void {
        switch (json_name) {
            json.Value.Object => |map| {
                inline for (@typeInfo(Name).Struct.fields) |field| {
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
                                        @compileLog("Name nonexhaustive field_type switch");
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
                    this.normal_form = try strCopyAlloc(str, ator);
                } else {
                    this.normal_form = str;
                }
            },
            else => { return FromJsonError.bad_type; },
        }
    }
    pub fn free(this: *Name, ator: Allocator) void {
        inline for (@typeInfo(Name).Struct.fields) |field| {
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
                else => { @compileLog("Name.free() nonexhaustive field_type switch"); },
            }
        }
    }
};

pub const Surname = struct {
    male_form: []const u8 = "",
    female_form: ?[]const u8 = null,

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
                                        @compileLog("Name nonexhaustive field_type switch");
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
                else => { @compileLog("Surname.free() nonexhaustive field_type switch"); }
            }
        }
    }
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

pub const Date = struct {
    day: ?u8 = null,
    month: ?u8 = null,
    year: ?i32 = null,

    pub const ValidationError = error { invalid_day, invalid_month, invalid_year, };
    pub const FromJsonError = error { bad_type, bad_field, bad_field_val, };
    const month2daycount = [12]u8{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    pub fn validate(self: Date) ValidationError!void {
        if (self.year) |year| {
            if (year == 0) {
                return ValidationError.invalid_year;
            }
        }
        if (self.month) |month| {
            if (month == 0 or month > 12) {
                return ValidationError.invalid_month;
            }
            if (self.day) |day| {
                if (month != 2) {
                    if (day == 0 or day > Date.month2daycount[month-1]) {
                        return ValidationError.invalid_day;
                    }
                } else {
                    if (day == 0 or day > 29) {
                        return ValidationError.invalid_day;
                    }
                }
                if (self.year) |year| {
                    if (month == 2 and (
                            @rem(year, 400) == 0 or (
                                @rem(year, 100) != 0 and @rem(year, 4) == 0
                            )
                        )) {
                        // leap year
                        if (day == 0 or day > 29) {
                            return ValidationError.invalid_day;
                        }
                    } else {
                        if (day == 0 or day > Date.month2daycount[month-1]) {
                            return ValidationError.invalid_day;
                        }
                    }
                }
            }
        } else {
            if (self.day) |day| {
                if (day == 0 or day > 31)
                    return ValidationError.invalid_day;
            }
        }
    }
    pub fn dmy(d: u8, m: u8, y: i32) ValidationError!Date {
        const res = Date{.day=d, .month=m, .year=y};
        try res.validate();
        return res;
    }
    pub fn initFromJson(
        this: *Date,
        json_date: json.Value,
        options: Person.FromJsonOptions,
    ) !void {
        _ = options;
        switch (json_date) {
            json.Value.Object => |map| {
                if (map.get("day")) |d| {
                    switch (d) {
                        json.Value.Integer => |int| {
                            if (int > 0 and int <= ~@as(u8, 0)) {
                                this.day = @intCast(@typeInfo(@TypeOf(this.day)).Optional.child, int);
                            } else {
                                return FromJsonError.bad_field_val;
                            }
                        },
                        else => { return FromJsonError.bad_field; },
                    }
                }
                if (map.get("month")) |m| {
                    switch (m) {
                        json.Value.Integer => |int| {
                            if (int > 0 and int <= ~@as(u8, 0)) {
                                this.month = @intCast(@typeInfo(@TypeOf(this.month)).Optional.child, int);
                            } else {
                                return FromJsonError.bad_field_val;
                            }
                        },
                        else => { return FromJsonError.bad_field; },
                    }
                }
                if (map.get("year")) |y| {
                    switch (y) {
                        json.Value.Integer => |int| {
                            if (
                                int >=  @bitReverse(i32, 1) and
                                int <= ~@bitReverse(i32, 1)
                            ) {
                                this.year = @intCast(@typeInfo(@TypeOf(this.year)).Optional.child, int);
                            }
                        },
                        else => { return FromJsonError.bad_field; },
                    }
                }
                try this.validate();
            },
            else => { return FromJsonError.bad_type; },
        }
    }
    pub fn free(this: *Date, ator: Allocator) void {
        _ = this; _ = ator;
    }
};

pub const Notes = Patronymic; // so far both Patronymic and Notes are wrapped []const u8

const peter_full_source =
    \\{
    \\  "id": 1,
    \\  "name": {"normal_form": "Peter", "short_form": "Petya"},
    \\  "surname": {"male_form": "Zakharov", "female_form": "Zakharova"},
    \\  "patronymic": "Nikolaevich",
    \\  "sex": "male",
    \\  "birth_date": {"day": 3, "month": 2, "year": 2000},
    \\  "death_date": null,
    \\  "notes": null
    \\}
;
const peter_short_source =
    \\{
    \\  "id": 2,
    \\  "name": "Peter",
    \\  "surname": "Zakharov",
    \\  "patronymic": "Nikolaevich",
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
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(peter_full_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try expect(strEqual("Peter", peter.name.?.normal_form));
        try expect(strEqual("Petya", peter.name.?.short_form.?));
        try expect(null == peter.name.?.full_form);
    }
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(peter_short_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try expect(strEqual("Peter", peter.name.?.normal_form));
        try expect(null == peter.name.?.short_form);
        try expect(null == peter.name.?.full_form);
    }
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(mysterious_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try expect(null == peter.name);
        peter.name = .{.normal_form = try strCopyAlloc("", testing.allocator)};
    }
}

test "surname" {
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(peter_full_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try expect(strEqual("Zakharov", peter.surname.?.male_form));
        try expect(strEqual("Zakharova", peter.surname.?.female_form.?));
    }
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(peter_short_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try expect(strEqual("Zakharov", peter.surname.?.male_form));
        try expect(null == peter.surname.?.female_form);
    }
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(mysterious_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try expect(null == peter.surname);
    }
}

test "patronymic" {
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(peter_full_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try expect(strEqual("Nikolaevich", peter.patronymic.?.data));
    }
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(peter_short_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try expect(strEqual("Nikolaevich", peter.patronymic.?.data));
    }
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(mysterious_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try expect(null == peter.patronymic);
    }
}

test "sex" {
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(peter_full_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try expect(peter.sex.?.data == .male);
    }
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(peter_short_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try expect(peter.sex.?.data == .male);
    }
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(mysterious_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try expect(null == peter.sex);
    }
}

test "date" {
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(peter_full_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try expect(peter.birth_date.?.day.? == 3);
        try expect(peter.birth_date.?.month.? == 2);
        try expect(peter.birth_date.?.year.? == 2000);
        try expect(peter.death_date == null);
    }
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(peter_short_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try expect(peter.birth_date.?.day.? == 3);
        try expect(peter.birth_date.?.month.? == 2);
        try expect(peter.birth_date.?.year.? == 2000);
        try expect(peter.death_date == null);
    }
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(mysterious_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try expect(null == peter.birth_date);
        try expect(null == peter.death_date);
    }
}

test "notes" {
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(peter_full_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try expect(null == peter.notes);
    }
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(peter_short_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try expect(null == peter.notes);
    }
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(mysterious_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try expect(null == peter.notes);
    }
}

test "rename" {
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(peter_full_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try peter.rename(
            Name{.normal_form="Osetr"},
            .{.new_ator=testing.allocator, .del_ator=testing.allocator,},
        );
        try expect(strEqual(peter.name.?.normal_form, "Osetr"));
    }
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(peter_short_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try peter.rename(
            Name{.normal_form="Osetr"},
            .{.new_ator=testing.allocator, .del_ator=testing.allocator,},
        );
        try expect(strEqual(peter.name.?.normal_form, "Osetr"));
    }
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(mysterious_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try peter.rename(
            Name{.normal_form="Osetr"},
            .{.new_ator=testing.allocator, .del_ator=testing.allocator,},
        );
        try expect(strEqual(peter.name.?.normal_form, "Osetr"));
    }
}

test "set date" {
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var json_tree = try parser.parse(peter_full_source);
        defer json_tree.deinit();
        var json_peter = json_tree.root;
        var peter = Person{ .id=0 };
        try peter.initFromJson(json_peter, .{.ator=testing.allocator});
        defer peter.free(testing.allocator);
        try peter.setDate(Date{.day=2, .month=3, .year=2}, .birth);
        try peter.setDate(Date{.day=1, .month=1, .year=-1}, .death);
        try expect(peter.birth_date.?.day.? == 2);
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

