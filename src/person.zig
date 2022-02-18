const std = @import("std");
const date_module = @import("date.zig");
const Date = date_module.Date;
const notes_module = @import("notes.zig");
const Notes = notes_module.Notes;
const Allocator = std.mem.Allocator;
const json = std.json;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const logger = std.log.scoped(.ft);


pub const StrMgmt = enum {
    copy, move,
    pub fn asText(comptime options: StrMgmt) switch (options) {
        .copy => @TypeOf("copy"),
        .move => @TypeOf("move"),
    } {
        return switch (options) {
            .copy => "copy",
            .move => "move",
        };
    }
};


pub const Person = struct {
    id: Id,
    name: Name = .{},
    alternative_names: NameList = .{},
    // surname: Surname = .{},
    // alternative_surnames: SurnameList = .{},
    // patronymic: Patronymic = .{},
    // sex: ?Sex = null,
    birth_date: ?Date = null,
    death_date: ?Date = null,
    notes: Notes = .{},

    pub const Id = i64;
    // pub fn init(id: Id) Person {
    //     logger.debug("Person.init() w/ id={d}", .{id});
    //     var person: Person = undefined;
    //     person.id=id;
    //     inline for (@typeInfo(Person).Struct.fields) |field| {
    //         switch (field.field_type) {
    //             Id => {},
    //             ?Sex, ?Date => {
    //                 @field(person, field.name) = null;
    //             },
    //             else => {
    //                 @field(person, field.name) = field.field_type.init(ator);
    //             },
    //         }
    //     }
    // }
    pub fn deinit(this: *Person, ator: Allocator) void {
        logger.debug("Person.deinit() w/ id={d}, w/ ator.vtable={*}", .{this.id, ator.vtable});
        inline for (@typeInfo(Person).Struct.fields) |field| {
            switch (field.field_type) {
                Id, ?Sex, ?Date => {},
                else => {
                    @field(this, field.name).deinit(ator);
                },
            }
        }
    }

    pub const FromJsonError = error { bad_type, bad_field, };
    pub fn readFromJson(
        this: *Person,
        json_person: json.Value,
        comptime allocator: ?Allocator,
        comptime options: StrMgmt,
    ) !void {
        logger.debug("Person.readFromJson() w/ id={d}, options={s}", .{this.id, options.asText()});
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
                                    else => {
                                        logger.err(
                                            \\in Person.readFromJson()
                                            \\ j_person.get("id")
                                            \\ is not of type i64
                                            , .{}
                                        );
                                        return FromJsonError.bad_field;
                                    },
                                }
                            },
                            ?Date, ?Sex => {
                                switch (val) {
                                    json.Value.Null => {
                                        @field(this, field.name) = null;
                                    },
                                    else => {
                                        if (@field(this, field.name) == null) {
                                            @field(this, field.name) = .{};
                                            errdefer @field(this, fiels.name) = null;
                                            try @field(this, field.name).?.readFromJson(val);
                                        } else {
                                            try @field(this, field.name).?.readFromJson(val);
                                        }
                                    },
                                }
                            },
                            else => {
                                try @field(this, field.name).readFromJson(val, allocator, options);
                            },
                        }
                    }
                }
            },
            else => {
                logger.err(
                    "in Person.readFromJson() j_person is not of type {s}",
                    .{@typeName(json.ObjectMap)},
                );
                return FromJsonError.bad_type;
            },
        }
    }
    /// for testing purposes
    pub fn readFromJsonSourceStr(
        this: *Person,
        source_str: []const u8,
        ator: Allocator,
        comptime allocator: ?Allocator,
        comptime options: StrMgmt,
    ) !void {
        var parser = json.Parser.init(ator, false); // strings are copied in readFromJson
        defer parser.deinit();
        var tree = try parser.parse(source_str);
        defer tree.deinit();
        try this.readFromJson(tree.root, allocator, options);
    }

    pub fn rename(
        this: *Person,
        new_name_ptr: anytype,
        comptime allocator: ?Allocator,
        comptime options: StrMgmt,
    ) !void {
        logger.debug("Person.rename(): {s} -> {s}", .{this.name.getSome(), new_name_ptr.getSome()});
        switch (options) {
            .copy => {
                if (allocator) |ator| {
                    var copy = try new_name_ptr.copy(ator);
                    defer copy.deinit(ator);
                    this.name.swap(&copy);
                } else {
                    this.name = new_name_ptr.*;
                }
            },
            .move => {
                if (allocator) |ator| {
                    this.name.deinit(ator);
                }
                this.name = new_name_ptr.move();
            },
        }
    }
    pub fn setDate(this: *Person, date: Date, which: enum { birth, death, }) !void {
        logger.debug(
            "Person.setDate() /w id={d} on occasion of {s}",
            .{
                this.id,
                switch (which) {
                    .birth => "birth",
                    .death => "death",
                },
            },
        );
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

    pub fn deinit(this: *Name, ator: Allocator) void {
        logger.debug("Name.deinit() w/ name={s}, ator={*}", .{this.getSome(), ator.vtable});
        inline for (@typeInfo(Name).Struct.fields) |field| {
            switch (field.field_type) {
                []const u8 => {
                    ator.free(@field(this, field.name));
                },
                else => {
                    @compileError("Name.deinit() nonexhaustive field_type switch");
                },
            }
        }
    }

    pub const FromJsonError = error { bad_type, bad_field, };
    pub fn readFromJson(
        this: *Name,
        json_name: json.Value,
        comptime allocator: ?Allocator,
        comptime options: StrMgmt,
    ) !void {
        logger.debug("Name.readFromJson() w/ options={s}", .{options.asText()});
        switch (json_name) {
            json.Value.Object => |map| {
                switch (options) {
                    .copy => {
                        if (allocator) |ator| {
                            try this.copyAllocFromJsonObj(map, ator);
                        } else {
                            try this.copyNoAllocFromJsonObj(map);
                        }
                    },
                    .move => {
                        try this.moveFromJsonObj(map, allocator);
                    },
                }
            },
            json.Value.String => |*str| {
                switch (options) {
                    .copy => {
                        if (allocator) |ator| {
                            var slice = try strCopyAlloc(str.*, this.ator);
                            this.deinit(ator);
                            this = Name{};
                            this.normal_form = slice;
                        } else {
                            this = Name{};
                            this.normal_form = str;
                        }
                    },
                    .move => {
                        if (allocator) |ator| {
                            this.deinit(ator);
                        }
                        this = Name{};
                        this.normal_form = str.*;
                        str.* = "";
                    },
                }
            },
            else => {
                logger.err(
                    \\in Name.readFromJson() j_name is neither {s} nor {s}
                    , .{@typeName(json.ObjectMap), @typeName([]const u8)}
                );
                return FromJsonError.bad_type;
            },
        }
    }
    fn copyAllocFromJsonObj(this: *Name, map: json.ObjectMap, ator: Allocator) !void {
        var name_copy = Name{};
        errdefer name_copy.deinit(ator);
        inline for (@typeInfo(Name).Struct.fields) |field| {
            if (map.get(field.name)) |*val| {
                switch (field.field_type) {
                    []const u8 => {
                        switch (val.*) {
                            json.Value.String, json.Value.NumberString => |*str| {
                                @field(name_copy, field.name) = try strCopyAlloc(str.*, ator);
                            },
                            else => {
                                logger.err(
                                    \\in Name.readFromJson() j_name.get("{s}")
                                    \\ is not of type {s}
                                    , .{field.name, @typeName([]const u8)}
                                );
                                return FromJsonError.bad_field;
                            },
                        }
                    },
                    else => {
                        @compileError("Name.readFromJson() nonexhaustive switch on field_type");
                    },
                }
            }
        }
        this.deinit(ator);
        this.* = name_copy;
    }
    fn copyNoAllocFromJsonObj(this: *Name, map: json.ObjectMap) !void {
        var name_copy = Name{};
        inline for (@typeInfo(Name).Struct.fields) |field| {
            if (map.get(field.name)) |*val| {
                switch (field.field_type) {
                    []const u8 => {
                        switch (val.*) {
                            json.Value.String, json.Value.NumberString => |str| {
                                @field(name_copy, field.name) = str;
                            },
                            else => {
                                logger.err(
                                    \\in Name.readFromJson() j_name.get("{s}")
                                    \\ is not of type {s}
                                    , .{field.name, @typeName([]const u8)}
                                );
                                return FromJsonError.bad_field;
                            },
                        }
                    },
                    else => {
                        @compileError("Name.readFromJson() nonexhaustive switch on field_type");
                    },
                }
            }
        }
        this.* = name_copy;
    }
    fn moveFromJsonObj(this: *Name, map: json.ObjectMap, allocator: ?Allocator) !void {
        var name_copy = Name{};
        errdefer {
            // put back loop
            inline for (@typeInfo(Name).Struct.fields) |field| {
                if (map.getPtr(field.name)) |val_ptr| {
                    switch (val_ptr.*) {
                        json.String, json.Value.NumberString => |*str| {
                            if (!strEqual(@field(name_copy, field.name), "")) {
                                str.* = @field(name_copy, field.name);
                            }
                        },
                        else => {}, // can't throw errors here
                    }
                }
            }
        }
        inline for (@typeInfo(Name).Struct.fields) |field| {
            if (map.getPtr(field.name)) |val_ptr| {
                switch (field.field_type) {
                    []const u8 => {
                        switch (val_ptr.*) {
                            json.Value.String, json.Value.NumberString => |*str| {
                                @field(name_copy, field.name) = str.*;
                                str.* = "";
                            },
                            else => {
                                logger.err(
                                    \\in Name.readFromJson() j_name.get("{s}")
                                    \\ is not of type {s}
                                    , .{field.name, @typeName([]const u8)}
                                );
                                return FromJsonError.bad_field;
                            },
                        }
                    },
                    else => {
                        @compileError("Name.readFromJson() nonexhaustive switch on field_type");
                    },
                }
            }
        }
        if (allocator) |ator| {
            this.deinit(ator);
        }
        this.* = name_copy;
    }

    pub fn getSome(self: Name) []const u8 {
        if (self.normal_form.len > 0) {
            return self.normal_form;
        } else if (self.full_form.len > 0) {
            return self.full_form;
        } else if (self.short_form.len > 0) {
            return self.short_form;
        } else {
            return "";
        }
    }
};


pub const NameList = struct {
    data: ArrayListUnmanaged(Name) = .{},

    pub fn deinit(this: *NameList, ator: Allocator) void {
        logger.debug("NameList.deinit() w/ ator={*}", .{ator.vtable});
        for (this.data.items) |name| {
            name.deinit(ator);
        }
        this.data.deinit(ator);
    }

    pub const FromJsonError = error { bad_type, bad_item, allocator_required, };
    pub fn readFromJson(
        this: *NameList,
        json_name_list: json.Value,
        comptime allocator: ?Allocator,
        comptime options: StrMgmt,
    ) !void {
        if (allocator) |ator| {
            logger.debug("NameList.readFromJson() w/ options={s}", .{options.asText()});
            var copy_list = NameList{};
            errdefer copy_list.deinit(ator);
            var last_read_name: ?Name = null;
            switch (json_name_list) {
                json.Value.Array => |arr| {
                    copy_list.data.ensureTotalCapacity(arr.size);
                    for (arr.items) |item| {
                        var name = Name{};
                        errdefer name.deinit(ator);
                        name.readFromJson(item) catch |err| {
                            if (last_read_name) |lrn| {
                                logger.err(
                                    \\in NameList.readFromJson()
                                    \\ last successfully read name is {s}
                                    \\ initial NameList remains unchanged
                                    , .{lrn.normal_form}
                                );
                            } else {
                                logger.err(
                                    \\in NameList.readFromJson()
                                    \\ no name could be read
                                    , .{}
                                );
                            }
                            return err;
                        };
                        last_read_name = name;
                        try copy_list.data.append(ator, name);
                    }
                },
                else => {
                    logger.err(
                        \\in NameList.readFromJson()
                        \\ j_name_list is not of type {s}
                        , .{@typeName(json.Array)}
                    );
                    return FromJsonError.bad_type;
                },
            }
            this.deinit(ator);
            this.* = copy_list;
        } else {
            logger.err("in NameList.readFromJson() allocator required", .{});
            return FromJsonError.allocator_required;
        }
    }
};


pub const Surname = struct {
    male_form: []const u8 = "",
    female_form: []const u8 = "",

    pub fn deinit(this: *Surname, ator: Allocator) void {
        logger.debug("Surname.deinit() w/ surname={s}, ator={*}", .{this.getSome(), ator.vtable});
        inline for (@typeInfo(Surname).Struct.fields) |field| {
            switch (field.field_type) {
                []const u8 => {
                    ator.free(@field(this, field.name));
                },
                else => {
                    @compileError("Surname.deinit() nonexhaustive switch on field_type");
                },
            }
        }
    }

    pub const FromJsonError = error { bad_type, bad_field, };
    pub fn readFromJson(
        this: *Surname,
        json_surname: json.Value,
        comptime allocator: ?Allocator,
        comptime options: StrMgmt,
    ) !void {
        logger.debug("Surname.readFromJson() w/ options={s}", .{options.asText()});
        switch (json_surname) {
            json.Value.Object => |map| {
                var surname_copy = Surname{};
                switch (options) {
                    .copy => {
                        if (allocator) |ator| {
                            try this.copyAllocFromJsonObj(map, ator);
                        } else {
                            try this.copyNoAllocFromJsonObj(map);
                        }
                    },
                    .move => {
                        try this.moveFromJsonObj(map, ator);
                    },
                }
            },
            json.Value.String => |*str| {
                switch (options) {
                    .copy => {
                        if (allocator) |ator| {
                            var slice = try strCopyAlloc(str.*, this.ator);
                            this.deinit(ator);
                            this = Surname{};
                            this.male_form = slice;
                        } else {
                            this = Surname{};
                            this.male_form = str;
                        }
                    },
                    .move => {
                        if (allocator) |ator| {
                            this.deinit(ator);
                        }
                        this = Surname{};
                        this.male_form = str.*;
                        str.* = "";
                    },
                }
            },
            else => {
                logger.err(
                    \\in Surname.readFromJson() j_surname is neither {s} nor {s}
                    , .{@typeName(json.ObjectMap), @typeName([]const u8)}
                );
                return FromJsonError.bad_type;
            },
        }
    }
    fn copyAllocFromJsonObj(this: *Surname, map: json.ObjectMap, ator: Allocator) !void {
        var surname_copy = Surname{};
        errdefer surname_copy.deinit(ator);
        inline for (@typeInfo(Surname).Struct.fields) |field| {
            if (map.get(field.name)) |*val| {
                switch (field.field_type) {
                    []const u8 => {
                        switch (val.*) {
                            json.Value.String, json.Value.NumberString => |*str| {
                                @field(surname_copy, field.name) = try strCopyAlloc(str.*, ator);
                            },
                            else => {
                                logger.err(
                                    \\in Surname.readFromJson() j_surname.get("{s}")
                                    \\ is not of type {s}
                                    , .{field.name, @typeName([]const u8)}
                                );
                                return FromJsonError.bad_field;
                            },
                        }
                    },
                    else => {
                        @compileError("Surname.readFromJson() nonexhaustive switch on field_type");
                    },
                }
            }
        }
        this.deinit(ator);
        this.* = surname_copy;
    }
    fn copyNoAllocFromJsonObj(this: *Surname, map: json.ObjectMap) !void {
        var surname_copy = Surname{};
        inline for (@typeInfo(Surname).Struct.fields) |field| {
            if (map.get(field.name)) |*val| {
                switch (field.field_type) {
                    []const u8 => {
                        switch (val.*) {
                            json.Value.String, json.Value.NumberString => |str| {
                                @field(surname_copy, field.name) = str;
                            },
                            else => {
                                logger.err(
                                    \\in Surname.readFromJson() j_surname.get("{s}")
                                    \\ is not of type {s}
                                    , .{field.name, @typeName([]const u8)}
                                );
                                return FromJsonError.bad_field;
                            },
                        }
                    },
                    else => {
                        @compileError("Surname.readFromJson() nonexhaustive switch on field_type");
                    },
                }
            }
        }
        this.* = surname_copy;
    }
    fn moveFromJsonObj(this: *Surname, map: json.ObjectMap, allocator: ?Allocator) !void {
        var surname_copy = Surname{};
        errdefer {
            // put back loop
            inline for (@typeInfo(Surname).Struct.fields) |field| {
                if (map.getPtr(field.name)) |val_ptr| {
                    switch (val_ptr.*) {
                        json.String, json.Value.NumberString => |*str| {
                            if (!strEqual(@field(surname_copy, field.name), "")) {
                                str.* = @field(surname_copy, field.name);
                            }
                        },
                        else => {}, // can't throw errors here
                    }
                }
            }
        }
        inline for (@typeInfo(Surname).Struct.fields) |field| {
            if (map.getPtr(field.name)) |val_ptr| {
                switch (field.field_type) {
                    []const u8 => {
                        switch (val_ptr.*) {
                            json.Value.String, json.Value.NumberString => |*str| {
                                @field(surname_copy, field.name) = str.*;
                                str.* = "";
                            },
                            else => {
                                logger.err(
                                    \\in Surname.readFromJson() j_surname.get("{s}")
                                    \\ is not of type {s}
                                    , .{field.name, @typeName([]const u8)}
                                );
                                return FromJsonError.bad_field;
                            },
                        }
                    },
                    else => {
                        @compileError("Surname.readFromJson() nonexhaustive switch on field_type");
                    },
                }
            }
        }
        if (allocator) |ator| {
            this.deinit(ator);
        }
        this.* = surname_copy;
    }

    pub fn getSome(self: Surname) []const u8 {
        if (self.male_form.len > 0) {
            return self.male_form;
        } else if (self.female_form.len > 0) {
            return self.female_form;
        } else {
            return "";
        }
    }
};


// // TODO
pub const SurnameList = struct {
    data: ArrayListUnmanaged(Surname),
    
    pub fn deinit(this: *SurnameList, ator: Allocator) void {
        logger.debug("SurnameList.deinit() w/ ator={*}", .{ator.vtable});
        for (this.data.items) |*surname| {
            surname.deinit(ator);
        }
        this.data.deinit(ator);
    }

    pub const FromJsonError = error { bad_type, bad_field, };
    pub fn readFromJson(
        this: *SurnameList,
        json_surname_list: json.Value,
        allocator: ?Allocator,
        options: StrMgmt,
    ) !void {
        var copy_list = ArrayListUnmanaged(Surname).init(this.ator);
        errdefer {
            if (allocator) |ator|
            for (copy_list.items) |*name| {
                name.deinit();
            }
            copy_list.deinit();
        }
        switch (json_surname_list) {
            json.Array => |arr| {
                for (arr.items) |item| {
                    var surname = Surname.init(this.ator);
                    errdefer surname.deinit();
                    try surname.readFromJson(item);
                    try copy_list.append(surname);
                }
            },
            else => { return FromJsonError.bad_type; },
        }
        this.deinit();
        this.data = copy_list;
    }
};


// pub const Patronymic = struct {
//     data: []const u8 = "",
//     ator: Allocator,

//     pub fn init(ator: Allocator) Patronymic {
//         return Patronymic{.ator=ator};
//     }
//     pub fn deinit(this: *Patronymic) void {
//         this.ator.free(this.data);
//     }

//     pub const FromJsonError = error { bad_type, bad_field, };
//     pub fn readFromJson(this: *Patronymic, json_patronymic: json.Value) !void {
//         switch (json_patronymic) {
//             json.Value.String, json.Value.NumberString => |str| {
//                 var slice = try strCopyAlloc(str, this.ator);
//                 this.ator.free(this.data);
//                 this.data = slice;
//             },
//             else => { return FromJsonError.bad_type; },
//         }
//     }
// };


// pub const Sex = struct {
//     data: enum(u1) { male = 1, female = 0, } = .male,

//     pub const FromJsonError = error { bad_type, bad_field, };
//     pub fn readFromJson(this: *Sex, json_sex: json.Value) !void {
//         switch (json_sex) {
//             json.Value.String => |str| {
//                 if (strEqual("male", str)) {
//                     this.data = .male;
//                 } else if (strEqual("female", str)) {
//                     this.data = .female;
//                 } else {
//                     return FromJsonError.bad_field;
//                 }
//             },
//             json.Value.Bool => |is_male| {
//                 if (is_male) {
//                     this.data = .male;
//                 } else {
//                     this.data = .female;
//                 }
//             },
//             json.Value.Integer => |int| {
//                 if (int == 1) {
//                     this.data = .male;
//                 } else if (int == 0) {
//                     this.data = .female;
//                 } else {
//                     return FromJsonError.bad_field;
//                 }
//             },
//             else => { return FromJsonError.bad_type; },
//         }
//     }
// };



const testing = std.testing;
const expect = testing.expect;

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
        var human = Person.init(0, testing.allocator);
        try human.readFromJsonSourceStr(human_full_source);
        defer human.free(testing.allocator);
        try expect(strEqual("Human", human.name.?.normal_form));
        try expect(strEqual("Hum", human.name.?.short_form.?));
        try expect(null == human.name.?.full_form);
    }
    {
        var human = Person.init(0, testing.allocator);
        try human.readFromJsonSourceStr(human_short_source);
        defer human.free(testing.allocator);
        try expect(strEqual("Human", human.name.?.normal_form));
        try expect(null == human.name.?.short_form);
        try expect(null == human.name.?.full_form);
    }
    {
        var human = Person.init(0, testing.allocator);
        try human.readFromJsonSourceStr(mysterious_source);
        defer human.free(testing.allocator);
        try expect(null == human.name);
        human.name = .{.normal_form = try strCopyAlloc("", testing.allocator)};
    }
}

// test "surname" {
//     {
//         var human = Person.init(0, testing.allocator);
//         try human.readFromJsonSourceStr(human_full_source);
//         defer human.free(testing.allocator);
//         try expect(strEqual("Ivanov", human.surname.?.male_form));
//         try expect(strEqual("Ivanova", human.surname.?.female_form.?));
//     }
//     {
//         var human = Person.init(0, testing.allocator);
//         try human.readFromJsonSourceStr(human_short_source);
//         defer human.free(testing.allocator);
//         try expect(strEqual("Ivanov", human.surname.?.male_form));
//         try expect(null == human.surname.?.female_form);
//     }
//     {
//         var human = Person.init(0, testing.allocator);
//         try human.readFromJsonSourceStr(mysterious_source);
//         defer human.free(testing.allocator);
//         try expect(null == human.surname);
//     }
// }

// test "patronymic" {
//     {
//         var human = Person.init(0, testing.allocator);
//         try human.readFromJsonSourceStr(human_full_source);
//         defer human.free(testing.allocator);
//         try expect(strEqual("Fathersson", human.patronymic.?.data));
//     }
//     {
//         var human = Person.init(0, testing.allocator);
//         try human.readFromJsonSourceStr(human_short_source);
//         defer human.free(testing.allocator);
//         try expect(strEqual("Fathersson", human.patronymic.?.data));
//     }
//     {
//         var human = Person.init(0, testing.allocator);
//         try human.readFromJsonSourceStr(mysterious_source);
//         defer human.free(testing.allocator);
//         try expect(null == human.patronymic);
//     }
// }

// test "sex" {
//     {
//         var human = Person.init(0, testing.allocator);
//         try human.readFromJsonSourceStr(human_full_source);
//         defer human.free(testing.allocator);
//         try expect(human.sex.?.data == .male);
//     }
//     {
//         var human = Person.init(0, testing.allocator);
//         try human.readFromJsonSourceStr(human_short_source);
//         defer human.free(testing.allocator);
//         try expect(human.sex.?.data == .male);
//     }
//     {
//         var human = Person.init(0, testing.allocator);
//         try human.readFromJsonSourceStr(mysterious_source);
//         defer human.free(testing.allocator);
//         try expect(null == human.sex);
//     }
// }

test "date" {
    {
        var human = Person.init(0, testing.allocator);
        try human.readFromJsonSourceStr(human_full_source);
        defer human.free(testing.allocator);
        try expect(human.birth_date.?.day.? == 3);
        try expect(human.birth_date.?.month.? == 2);
        try expect(human.birth_date.?.year.? == 2000);
        try expect(human.death_date == null);
    }
    {
        var human = Person.init(0, testing.allocator);
        try human.readFromJsonSourceStr(human_short_source);
        defer human.free(testing.allocator);
        try expect(human.birth_date.?.day.? == 3);
        try expect(human.birth_date.?.month.? == 2);
        try expect(human.birth_date.?.year.? == 2000);
        try expect(human.death_date == null);
    }
    {
        var human = Person.init(0, testing.allocator);
        try human.readFromJsonSourceStr(mysterious_source);
        defer human.free(testing.allocator);
        try expect(null == human.birth_date);
        try expect(null == human.death_date);
    }
}

test "notes" {
    {
        var human = Person.init(0, testing.allocator);
        try human.readFromJsonSourceStr(human_full_source);
        defer human.free(testing.allocator);
        try expect(null == human.notes);
    }
    {
        var human = Person.init(0, testing.allocator);
        try human.readFromJsonSourceStr(human_short_source);
        defer human.free(testing.allocator);
        try expect(null == human.notes);
    }
    {
        var human = Person.init(0, testing.allocator);
        try human.readFromJsonSourceStr(mysterious_source);
        defer human.free(testing.allocator);
        try expect(null == human.notes);
    }
}

test "rename" {
    {
        var human = Person.init(0, testing.allocator);
        try human.readFromJsonSourceStr(human_full_source);
        defer human.free(testing.allocator);
        try human.rename(
            Name{.normal_form="Osetr"},
            .{.new_ator=testing.allocator, .del_ator=testing.allocator,},
        );
        try expect(strEqual(human.name.?.normal_form, "Osetr"));
    }
    {
        var human = Person.init(0, testing.allocator);
        try human.readFromJsonSourceStr(human_short_source);
        defer human.free(testing.allocator);
        try human.rename(
            Name{.normal_form="Osetr"},
            .{.new_ator=testing.allocator, .del_ator=testing.allocator,},
        );
        try expect(strEqual(human.name.?.normal_form, "Osetr"));
    }
    {
        var human = Person.init(0, testing.allocator);
        try human.readFromJsonSourceStr(mysterious_source);
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
        var human = Person.init(0, testing.allocator);
        try human.readFromJsonSourceStr(human_full_source);
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
