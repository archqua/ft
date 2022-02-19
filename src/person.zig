const std = @import("std");
const date_module = @import("date.zig");
const Date = date_module.Date;
const notes_module = @import("notes.zig");
const Notes = notes_module.Notes;
const Allocator = std.mem.Allocator;
const json = std.json;
const dict_module = @import("dict.zig");
const DictArrayUnmanaged = dict_module.DictArrayUnmanaged;
const logger = std.log.scoped(.ft);


// probably only StrMgmt.copy should ever be used
// StrMgmt.move seems ill
// sex field's behaviour is not affected
pub const StrMgmt = enum {
    copy, move, weak,
    pub fn asText(comptime options: StrMgmt) switch (options) {
        .copy => @TypeOf("copy"),
        .move => @TypeOf("move"),
        .weak => @TypeOf("weak"),
    } {
        return switch (options) {
            .copy => "copy",
            .move => "move",
            .weak => "weak",
        };
    }
    pub fn asEnumLiteral(comptime options: StrMgmt) @TypeOf(.enum_literal) {
        return switch (options) {
            .copy => .copy,
            .move => .move,
            .weak => .weak,
        };
    }
};


pub const Person = struct {
    id: Id,
    name: Name = .{},
    alternative_names: NameList = .{},
    surname: Surname = .{},
    alternative_surnames: SurnameList = .{},
    patronymic: Patronymic = .{},
    sex: ?Sex = null,
    birth_date: ?Date = null,
    death_date: ?Date = null,
    notes: Notes = .{},
    // these are by-blood
    father_id: ?Id = null,
    mother_id: ?Id = null,
    mitochondrial_mother_id: ?Id = null,

    pub const Id = i64;
    pub fn deinit(this: *Person, ator: Allocator) void {
        logger.debug("Person.deinit() w/ id={d}, w/ ator.vtable={*}", .{this.id, ator.vtable});
        inline for (@typeInfo(Person).Struct.fields) |field| {
            switch (field.field_type) {
                Id, ?Id, ?Sex, ?Date => {},
                else => {
                    @field(this, field.name).deinit(ator);
                },
            }
        }
    }

    pub const FromJsonError = error { bad_type, bad_field, };
    pub fn readFromJson(
        this: *Person,
        json_person: *json.Value,
        comptime allocator: ?Allocator,
        comptime options: StrMgmt,
    ) !void {
        AOCheck(allocator, options);
        logger.debug("Person.readFromJson() w/ id={d}, options={s}", .{this.id, options.asText()});
        switch (json_person.*) {
            json.Value.Object => |*map| {
                inline for (@typeInfo(Person).Struct.fields) |field| {
                    if (map.getPtr(field.name)) |val_ptr| {
                        switch (field.field_type) {
                            Id => {
                                switch (val_ptr.*) {
                                    json.Value.Integer => |int| {
                                        this.id = int;
                                    },
                                    else => {
                                        logger.err(
                                            "in Person.readFromJson()" ++
                                            " j_person.get(\"id\")" ++
                                            " is not of type {s}"
                                            , .{"json.Integer"}
                                        );
                                        return FromJsonError.bad_field;
                                    },
                                }
                            },
                            ?Id => {
                                switch (val_ptr.*) {
                                    json.Value.Integer => |int| {
                                        @field(this, field.name) = int;
                                    },
                                    json.Value.Null => {
                                        @field(this, field.name) = null;
                                    },
                                    else => {
                                        logger.err(
                                            "in Person.readFromJson()" ++
                                            " j_person.get(\"{s}\")" ++
                                            " is of neither type {s} not {s}"
                                            , .{field.name, "json.Integer", "json.Null"}
                                        );
                                        return FromJsonError.bad_field;
                                    },
                                }
                            },
                            ?Date, ?Sex => {
                                switch (val_ptr.*) {
                                    json.Value.Null => {
                                        @field(this, field.name) = null;
                                    },
                                    else => {
                                        if (null == @field(this, field.name)) {
                                            @field(this, field.name) = .{};
                                            errdefer @field(this, field.name) = null;
                                            try @field(this, field.name).?
                                                    .readFromJson(val_ptr.*);
                                        } else {
                                            try @field(this, field.name).?
                                                    .readFromJson(val_ptr.*);
                                        }
                                    },
                                }
                            },
                            else => {
                                try @field(this, field.name)
                                        .readFromJson(val_ptr, allocator, options.asEnumLiteral());
                            },
                        }
                    }
                }
            },
            else => {
                logger.err(
                    "in Person.readFromJson() j_person is not of type {s}",
                    .{"json.ObjectMap"},
                );
                return FromJsonError.bad_type;
            },
        }
    }
    /// for testing purposes
    pub fn readFromJsonSourceStr(
        this: *Person,
        source_str: []const u8,
        comptime ator: Allocator,
        comptime options: StrMgmt,
    ) !void {
        // TODO should only .copy be allowed???
        var parser = json.Parser.init(ator, false); // strings are copied in readFromJson
        defer parser.deinit();
        var tree = try parser.parse(source_str);
        defer tree.deinit();
        try this.readFromJson(&tree.root, ator, options);
    }

    // pub fn rename(
    //     this: *Person,
    //     new_name_ptr: anytype,
    //     comptime allocator: ?Allocator,
    //     comptime options: StrMgmt,
    // ) !void {
    //     AOCheck(allocator, options);
    //     logger.debug("Person.rename(): {s} -> {s}", .{this.name.getSome(), new_name_ptr.getSome()});
    //     switch (options) {
    //         .copy => {
    //             if (allocator) |ator| {
    //                 var copy = try new_name_ptr.copy(ator);
    //                 defer copy.deinit(ator);
    //                 this.name.swap(&copy);
    //             } else {
    //                 unreachable; // AOCheck()
    //             }
    //         },
    //         .move => {
    //             this.name = new_name_ptr.move();
    //         },
    //         .weak => {
    //             this.name = new_name_ptr.*;
    //         },
    //     }
    // }
    pub fn setDate(this: *Person, date: Date, which: enum { birth, death, }) !void {
        logger.debug(
            "Person.setDate() /w person.id={d} for event '{s}'",
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
        json_name: *json.Value,
        comptime allocator: ?Allocator,
        comptime options: StrMgmt,
    ) !void {
        AOCheck(allocator, options);
        logger.debug("Name.readFromJson() w/ options={s}", .{options.asText()});
        switch (json_name.*) {
            json.Value.Object => |*map| {
                switch (options) {
                    .copy => {
                        if (allocator) |ator| {
                            try this.deepCopyFromJsonObj(map.*, ator);
                        } else {
                            unreachable; // AOCheck()
                        }
                    },
                    .move => {
                        try this.moveFromJsonObj(map);
                    },
                    .weak => {
                        try this.weakCopyFromJsonObj(map.*);
                    },
                }
            },
            json.Value.String => |*str| {
                switch (options) {
                    .copy => {
                        if (allocator) |ator| {
                            this.normal_form = try strCopyAlloc(str.*, ator);
                        } else {
                            unreachable; // AOCheck()
                        }
                    },
                    .move => {
                        this.normal_form = str.*;
                        str.* = "";
                    },
                    .weak => {
                        this.normal_form = str.*;
                    },
                }
            },
            else => {
                logger.err(
                    "in Name.readFromJson() j_name is of neither type {s} nor {s}"
                    , .{"json.ObjectMap", "json.String"}
                );
                return FromJsonError.bad_type;
            },
        }
    }
    fn deepCopyFromJsonObj(this: *Name, map: json.ObjectMap, ator: Allocator) !void {
        inline for (@typeInfo(Name).Struct.fields) |field| {
            if (map.get(field.name)) |val| {
                switch (field.field_type) {
                    []const u8 => {
                        switch (val) {
                            json.Value.String, json.Value.NumberString => |str| {
                                @field(this, field.name) = try strCopyAlloc(str, ator);
                            },
                            else => {
                                logger.err(
                                    "in Name.readFromJson() j_name.get(\"{s}\")" ++
                                    " is not of type {s}"
                                    , .{field.name, "json.String"}
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
    }
    fn weakCopyFromJsonObj(this: *Name, map: json.ObjectMap) !void {
        inline for (@typeInfo(Name).Struct.fields) |field| {
            if (map.get(field.name)) |*val| {
                switch (field.field_type) {
                    []const u8 => {
                        switch (val.*) {
                            json.Value.String, json.Value.NumberString => |str| {
                                @field(this, field.name) = str;
                            },
                            else => {
                                logger.err(
                                    "in Name.readFromJson() j_name.get(\"{s}\")" ++
                                    " is not of type {s}"
                                    , .{field.name, "json.String"}
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
    }
    fn moveFromJsonObj(this: *Name, map: *json.ObjectMap) !void {
        inline for (@typeInfo(Name).Struct.fields) |field| {
            if (map.getPtr(field.name)) |val_ptr| {
                switch (field.field_type) {
                    []const u8 => {
                        switch (val_ptr.*) {
                            json.Value.String, json.Value.NumberString => |*str| {
                                @field(this, field.name) = str.*;
                                str.* = "";
                            },
                            else => {
                                logger.err(
                                    \\in Name.readFromJson() j_name.get("{s}")
                                    \\ is not of type {s}
                                    , .{field.name, "json.String"}
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
    data: DictArrayUnmanaged(Name) = .{},

    pub fn deinit(this: *NameList, ator: Allocator) void {
        logger.debug("NameList.deinit() w/ ator={*}", .{ator.vtable});
        var v_it = this.data.valueIterator();
        while (v_it.next()) |val_ptr| {
            val_ptr.deinit(ator);
        }
        this.data.deinit(ator);
    }

    pub const FromJsonError = error { bad_type, allocator_required, };
    pub fn readFromJson(
        this: *NameList,
        json_name_list: *json.Value,
        comptime allocator: ?Allocator,
        comptime options: StrMgmt,
    ) !void {
        if (allocator) |ator| { // can't check allocator at comptime
            logger.debug(
                "NameList.readFromJson() w/ ator={*}, options={s}"
                , .{ator.vtable, options.asText()}
            );
            var last_read_name: ?Name = null;
            switch (json_name_list.*) {
                json.Value.Object => |*obj| {
                    try this.data.data.ensureUnusedCapacity(ator, obj.count());
                    errdefer this.data.data.shrinkAndFree(ator, this.data.data.count());
                    var e_it = obj.iterator();
                    while (e_it.next()) |entry| {
                        var name = Name{};
                        errdefer {
                            switch (options) {
                                .copy, .move => {
                                    name.deinit(ator);
                                },
                                .weak => {},
                            }
                        }
                        name.readFromJson(
                            entry.value_ptr,
                            ator,
                            options,
                        ) catch |err| {
                            if (last_read_name) |lrn| {
                                logger.err(
                                    "in NameList.readFromJson()" ++
                                    " last successfully read name is {s}"
                                    , .{lrn.getSome()}
                                );
                            } else {
                                logger.err(
                                    "in NameList.readFromJson()" ++
                                    " no name could be read"
                                    , .{}
                                );
                            }
                            return err;
                        };
                        last_read_name = name;
                        try this.data.putAssumeCapacity(
                            entry.key_ptr.*,
                            name,
                            ator,
                            .{.kopy = (options == .copy)},
                        );
                        switch (options) {
                            .move => {
                                entry.key_ptr.* = "";
                            },
                            .copy, .weak => {},
                        }
                    }
                },
                else => {
                    logger.err(
                        "in NameList.readFromJson()" ++
                        " j_name_list is not of type {s}"
                        , .{"json.ObjectMap"}
                    );
                    return FromJsonError.bad_type;
                },
            }
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
        json_surname: *json.Value,
        comptime allocator: ?Allocator,
        comptime options: StrMgmt,
    ) !void {
        AOCheck(allocator, options);
        logger.debug("Surname.readFromJson() w/ options={s}", .{options.asText()});
        switch (json_surname.*) {
            json.Value.Object => |*map| {
                switch (options) {
                    .copy => {
                        if (allocator) |ator| {
                            try this.deepCopyFromJsonObj(map.*, ator);
                        } else {
                            unreachable; // AOCheck()
                        }
                    },
                    .move => {
                        try this.moveFromJsonObj(map);
                    },
                    .weak => {
                        if (allocator) |ator| {
                            try this.weakCopyFromJsonObj(map.*, ator);
                        } else {
                            unreachable; // AOCheck()
                        }
                    },
                }
            },
            json.Value.String => |*str| {
                switch (options) {
                    .copy => {
                        if (allocator) |ator| {
                            this.male_form = try strCopyAlloc(str.*, ator);
                        } else {
                            unreachable; // AOCheck()
                        }
                    },
                    .move => {
                        this.male_form = str.*;
                        str.* = "";
                    },
                    .weak => {
                        this.male_form = str.*;
                    },
                }
            },
            else => {
                logger.err(
                    "in Surname.readFromJson() j_surname is of neither type {s} nor {s}"
                    , .{"json.ObjectMap", "json.String"}
                );
                return FromJsonError.bad_type;
            },
        }
    }
    fn deepCopyFromJsonObj(this: *Surname, map: json.ObjectMap, ator: Allocator) !void {
        inline for (@typeInfo(Surname).Struct.fields) |field| {
            if (map.get(field.name)) |*val| {
                switch (field.field_type) {
                    []const u8 => {
                        switch (val.*) {
                            json.Value.String, json.Value.NumberString => |*str| {
                                @field(this, field.name) = try strCopyAlloc(str.*, ator);
                            },
                            else => {
                                logger.err(
                                    "in Surname.readFromJson() j_surname.get(\"{s}\")" ++
                                    " is not of type {s}"
                                    , .{field.name, "json.String"}
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
    }
    fn weakCopyFromJsonObj(this: *Surname, map: json.ObjectMap) !void {
        inline for (@typeInfo(Surname).Struct.fields) |field| {
            if (map.get(field.name)) |*val| {
                switch (field.field_type) {
                    []const u8 => {
                        switch (val.*) {
                            json.Value.String, json.Value.NumberString => |str| {
                                @field(this, field.name) = str;
                            },
                            else => {
                                logger.err(
                                    "in Surname.readFromJson() j_surname.get(\"{s}\")" ++
                                    " is not of type {s}"
                                    , .{field.name, "json.String"}
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
    }
    fn moveFromJsonObj(this: *Surname, map: *json.ObjectMap) !void {
        inline for (@typeInfo(Surname).Struct.fields) |field| {
            if (map.getPtr(field.name)) |val_ptr| {
                switch (field.field_type) {
                    []const u8 => {
                        switch (val_ptr.*) {
                            json.Value.String, json.Value.NumberString => |*str| {
                                @field(this, field.name) = str.*;
                                str.* = "";
                            },
                            else => {
                                logger.err(
                                    "in Surname.readFromJson() j_surname.get(\"{s}\")" ++
                                    " is not of type {s}"
                                    , .{field.name, "json.String"}
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


pub const SurnameList = struct {
    data: DictArrayUnmanaged(Surname) = .{},
    
    pub fn deinit(this: *SurnameList, ator: Allocator) void {
        logger.debug("SurnameList.deinit() w/ ator={*}", .{ator.vtable});
        var v_it = this.data.valueIterator();
        while (v_it.next()) |val_ptr| {
            val_ptr.deinit(ator);
        }
        this.data.deinit(ator);
    }

    pub const FromJsonError = error { bad_type, bad_field, allocator_required, };
    pub fn readFromJson(
        this: *SurnameList,
        json_surname_list: *json.Value,
        comptime allocator: ?Allocator,
        comptime options: StrMgmt,
    ) !void {
        if (allocator) |ator| {
            logger.debug(
                "Person.readFromJson() w/ ator={*}, options={s}"
                , .{ator.vtable, options.asText()}
            );
            var last_read_surname: ?Surname = null;
            switch (json_surname_list.*) {
                json.Value.Object => |*obj| {
                    try this.data.data.ensureUnusedCapacity(ator, obj.count());
                    errdefer this.data.data.shrinkAndFree(ator, this.data.count());
                    var e_it = obj.iterator();
                    while (e_it.next()) |entry| {
                        var surname = Surname{};
                        errdefer {
                            switch (options) {
                                .copy, .move => {
                                    surname.deinit(ator);
                                },
                                .weak => {},
                            }
                        }
                        surname.readFromJson(
                            entry.value_ptr,
                            ator,
                            options,
                        ) catch |err| {
                            if (last_read_surname) |lrs| {
                                logger.err(
                                    "in SurnameList.readFromJson()" ++
                                    " last successfully read surname is {s}"
                                    , .{lrs.getSome()}
                                );
                            } else {
                                logger.err(
                                    "in SurnameList.readFromJson()" ++
                                    " no surname could be read"
                                    , .{}
                                );
                            }
                            return err;
                        };
                        last_read_surname = surname;
                        try this.data.putAssumeCapacity(
                            entry.key_ptr.*,
                            surname,
                            ator,
                            .{.kopy = (options == .copy)},
                        );
                        switch (options) {
                            .move => {
                                entry.key_ptr.* = "";
                            },
                            .copy, .weak => {},
                        }
                    }
                },
                else => {
                    logger.err(
                        "in SurnameList.fromJsonError() j_surname_list" ++
                        " is not of type {s}"
                        , .{"json.ObjectMap"}
                    );
                    return FromJsonError.bad_type;
                },
            }
        } else {
            logger.err("in SurnameList.fromJsonError() allocator required", .{});
            return FromJsonError.allocator_required;
        }
    }
};


pub const Patronymic = WrappedString("Patronymic");
fn WrappedString(comptime type_name: []const u8) type {
return struct {
    data: []const u8 = "",

    pub fn deinit(this: *@This(), ator: Allocator) void {
        ator.free(this.data);
    }

    pub const FromJsonError = error { bad_type, };
    pub fn readFromJson(
        this: *@This(),
        json_patronymic: *json.Value,
        comptime allocator: ?Allocator,
        comptime options: StrMgmt,
    ) !void {
        AOCheck(allocator, options);
        logger.debug("{s}.readFromJson() w/ options={s}", .{type_name, options.asText()});
        switch (json_patronymic.*) {
            json.Value.String, json.Value.NumberString => |*str| {
                switch (options) {
                    .copy => {
                        if (allocator) |ator| {
                            this.data = try strCopyAlloc(str.*, ator);
                        } else {
                            unreachable; // AOCheck()
                        }
                    },
                    .move => {
                        this.data = str.*;
                        str.* = "";
                    },
                    .weak => {
                        this.data = str.*;
                    },
                }
            },
            else => {
                logger.err(
                    "in {s}.readFromJson() j_{s} is not of type {s}"
                    , .{type_name, "wrapped_string", "json.String"}
                );
                return FromJsonError.bad_type;
            },
        }
    }
};
}


pub const Sex = struct {
    data: UnderlyingEnum = .male,
    const UnderlyingInt = u1;
    pub const UnderlyingEnum = enum(UnderlyingInt) {
        male = 1, female = 0,
    };

    pub fn asChar(self: Sex) u8 {
        return switch (self) {
            .male => '1',
            .female => '0',
        };
    }
    pub fn asNum(self: Sex) UnderlyingInt {
        return switch (self) {
            .male => 1,
            .female => 0,
        };
    }
    pub fn asText(self: Sex) []const u8 {
        return switch (self) {
            .male => "male",
            .female => "female",
        };
    }

    pub const FromJsonError = error { bad_type, bad_field, };
    pub fn readFromJson(this: *Sex, json_sex: json.Value) !void {
        logger.debug("Sex.readFromJson()", .{});
        switch (json_sex) {
            json.Value.String => |str| {
                if (strEqual("male", str)) {
                    this.data = .male;
                } else if (strEqual("female", str)) {
                    this.data = .female;
                } else {
                    logger.err(
                        "in Sex.readFromJson() j_sex_str" ++
                        " is neither \"male\" nor \"female\""
                        , .{}
                    );
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
                    logger.err(
                        "in Sex.readFromJson() j_sex_int" ++
                        " is neither 1 nor 0"
                        , .{}
                    );
                    return FromJsonError.bad_field;
                }
            },
            else => {
                logger.err(
                    "in Sex.readFromJson() j_sex is of neither type {s}, {s} nor {s}"
                    , .{"json.String", "json.Bool", "json.Integer"}
                );
                return FromJsonError.bad_type;
            },
        }
    }
};



const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectError = testing.expectError;
const tator = testing.allocator;

const human_full_source =
    \\{
    \\  "id": 1,
    \\  "name": {"normal_form": "Human", "short_form": "Hum"},
    \\  "surname": {"male_form": "Ivanov", "female_form": "Ivanova"},
    \\  "patronymic": "Fathersson",
    \\  "sex": "male",
    \\  "birth_date": {"day": 3, "month": 2, "year": 2000},
    \\  "death_date": null,
    \\  "notes": "",
    \\  "father_id": 123,
    \\  "mother_id": 321,
    \\  "mitochondrial_mother_id": 321
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
    \\  "notes": "",
    \\  "father_id": 123,
    \\  "mother_id": 321
    \\}
;
const mysterious_source = 
    \\{
    \\  "id": 3,
    \\  "name": "",
    \\  "surname": "",
    \\  "patronymic": "",
    \\  "sex": null,
    \\  "notes": "",
    \\  "father_id": null,
    \\  "mother_id": null
    \\}
;

fn testName(src: []const u8, expected_name: Name) !void {
    var human = Person{.id = undefined};
    defer human.deinit(tator);
    try human.readFromJsonSourceStr(src, tator, .copy);
    inline for (@typeInfo(Name).Struct.fields) |field| {
        try expect(strEqual(
                @field(human.name, field.name),
                @field(expected_name, field.name),
            ));
    }
}
test "name" {
    try testName(human_full_source, Name{.normal_form="Human", .short_form="Hum"});
    try testName(human_short_source, Name{.normal_form="Human"});
    try testName(mysterious_source, Name{});
}

fn testSurname(src: []const u8, expected_surname: Surname) !void {
    var human = Person{.id = undefined};
    defer human.deinit(tator);
    try human.readFromJsonSourceStr(src, tator, .copy);
    inline for (@typeInfo(Surname).Struct.fields) |field| {
        try expect(strEqual(
                @field(human.surname, field.name),
                @field(expected_surname, field.name),
            ));
    }
}
test "surname" {
    try testSurname(human_full_source, Surname{.male_form="Ivanov", .female_form="Ivanova"});
    try testSurname(human_short_source, Surname{.male_form="Ivanov"});
    try testSurname(mysterious_source, Surname{});
}

fn testPatronymic(src: []const u8, expected_patronymic: Patronymic) !void {
    var human = Person{.id=undefined};
    defer human.deinit(tator);
    try human.readFromJsonSourceStr(src, tator, .copy);
    try expect(strEqual(expected_patronymic.data, human.patronymic.data));
}
test "patronymic" {
    try testPatronymic(human_full_source, Patronymic{.data="Fathersson"});
    try testPatronymic(human_short_source, Patronymic{.data="Fathersson"});
    try testPatronymic(mysterious_source, Patronymic{.data=""});
}

fn testSex(src: []const u8, expected_sex: ?Sex) !void {
    var human = Person{.id=undefined};
    defer human.deinit(tator);
    try human.readFromJsonSourceStr(src, tator, .copy);
    if (expected_sex) |es| {
        try expectEqual(es.data, human.sex.?.data);
    } else {
        try expectEqual(human.sex, null);
    }
}
test "sex" {
    try testSex(human_full_source, Sex{.data=.male});
    try testSex(human_short_source, Sex{.data=.male});
    try testSex(mysterious_source, null);
}

fn testDate(src: []const u8, expected_date: ?Date, comptime which: @TypeOf(.enum_literal)) !void {
    var human = Person{.id=undefined};
    defer human.deinit(tator);
    try human.readFromJsonSourceStr(src, tator, .copy);
    switch (which) {
        .birth => {
            if (expected_date) |ed| {
                inline for (@typeInfo(Date).Struct.fields) |field| {
                    try expectEqual(
                        @field(ed, field.name),
                        @field(human.birth_date.?, field.name),
                    );
                }
            } else {
                try expectEqual(human.birth_date, null);
            }
        },
        .death => {
            if (expected_date) |ed| {
                inline for (@typeInfo(Date).Struct.fields) |field| {
                    try expectEqual(
                        @field(ed, field.name),
                        @field(human.death_date.?, field.name),
                    );
                }
            } else {
                try expectEqual(human.death_date, null);
            }
        },
        else => {
            @compileError("testDate() nonexhaustive switch on which date");
        },
    }
}

test "date" {
    try testDate(human_full_source, Date{.day=3, .month=2, .year=2000}, .birth);
    try testDate(human_full_source, null, .death);
    try testDate(human_short_source, Date{.day=3, .month=2, .year=2000}, .birth);
    try testDate(human_short_source, null, .death);
    try testDate(mysterious_source, null, .birth);
    try testDate(mysterious_source, null, .death);
}

test "notes" {
    {
        var human = Person{.id=undefined};
        defer human.deinit(tator);
        try human.readFromJsonSourceStr(human_full_source, tator, .copy);
        try expect(strEqual("", human.notes.text));
        try expectEqual(@as(usize,0), human.notes.child_nodes.count());
    }
    {
        var human = Person{.id=undefined};
        defer human.deinit(tator);
        try human.readFromJsonSourceStr(human_short_source, tator, .copy);
        try expect(strEqual("", human.notes.text));
        try expectEqual(@as(usize,0), human.notes.child_nodes.count());
    }
    {
        var human = Person{.id=undefined};
        defer human.deinit(tator);
        try human.readFromJsonSourceStr(mysterious_source, tator, .copy);
        try expect(strEqual("", human.notes.text));
        try expectEqual(@as(usize,0), human.notes.child_nodes.count());
    }
}

fn testParentId(src: []const u8, expected_parent_id: ?Person.Id, who: enum {father, mother, mit_mother}) !void {
    var hum = Person{.id=undefined};
    defer hum.deinit(tator);
    try hum.readFromJsonSourceStr(src, tator, .copy);
    const parent_id = switch (who) {
        .father => hum.father_id,
        .mother => hum.mother_id,
        .mit_mother => hum.mitochondrial_mother_id,
    };
    try expectEqual(expected_parent_id, parent_id);
}
test "parent id" {
    try testParentId(human_full_source, 123, .father);
    try testParentId(human_full_source, 321, .mother);
    try testParentId(human_full_source, 321, .mit_mother);
    try testParentId(human_short_source, 123, .father);
    try testParentId(human_short_source, 321, .mother);
    try testParentId(human_short_source, null, .mit_mother);
    try testParentId(mysterious_source, null, .father);
    try testParentId(mysterious_source, null, .mother);
    try testParentId(mysterious_source, null, .mit_mother);
}

test "set date" {
    {
        var human = Person{.id=undefined};
        defer human.deinit(tator);
        try human.readFromJsonSourceStr(mysterious_source, tator, .copy);
        try human.setDate(Date{.day=2, .month=3, .year=2}, .birth);
        try human.setDate(Date{.day=1, .month=1, .year=-1}, .death);
        try expectEqual(human.birth_date.?.day.?, 2);
        try expectEqual(human.birth_date.?.month.?, 3);
        try expectEqual(human.birth_date.?.year.?, 2);
        try expectEqual(human.death_date.?.day.?, 1);
        try expectEqual(human.death_date.?.month.?, 1);
        try expectEqual(human.death_date.?.year.?, -1);
    }
}

fn testError(src: []const u8, expected_error: anyerror) !void {
    var human = Person{.id=undefined};
    defer human.deinit(tator);
    try expectError(expected_error, human.readFromJsonSourceStr(src, tator, .copy));
}
const bad_type_src_self =
\\"asdf"
;
const bad_type_src_name =
\\{
\\  "name": 1
\\}
;
const bad_type_src_surname =
\\{
\\  "surname": 1
\\}
;
const bad_type_src_name_list =
\\{
\\  "alternative_names": 2
\\}
;
const bad_type_src_surname_list =
\\{
\\  "alternative_surnames": ["a", "b", "c"]
\\}
;
const bad_type_src_date =
\\{
\\  "birth_date": "today"
\\}
;
const bad_type_src_sex =
\\{
\\  "sex": [1, 2, 3]
\\}
;
const bad_type_src_patronymic =
\\{
\\  "patronymic": 2
\\}
;
const bad_type_src_notes =
\\{
\\  "notes": 2
\\}
;
const bad_type_sources = [_][]const u8{
    bad_type_src_self,
    bad_type_src_name,
    bad_type_src_name_list,
    bad_type_src_surname,
    bad_type_src_surname_list,
    bad_type_src_date,
    bad_type_src_sex,
    bad_type_src_patronymic,
    bad_type_src_notes,
};
const bad_field_src_id =
\\{
\\  "id": "asdf"
\\}
;
const bad_field_src_name =
\\{
\\  "name": {
\\    "normal_form": 1
\\  }
\\}
;
const bad_field_src_name_list =
\\{
\\  "alternative_names": {
\\    "name": {
\\      "normal_form": 1
\\    }
\\  }
\\}
;
const bad_field_src_surname =
\\{
\\  "surname": {
\\    "male_form": 1
\\  }
\\}
;
const bad_field_src_surname_list =
\\{
\\  "alternative_surnames": {
\\    "surname": {
\\      "male_form": 1
\\    }
\\  }
\\}
;
const bad_field_src_date =
\\{
\\  "birth_date": {
\\    "day": "today"
\\  }
\\}
;
const bad_field_src_sex =
\\{
\\  "sex": 2
\\}
;
const bad_field_src_notes =
\\{
\\  "notes": {
\\    "text": "text",
\\    "child_nodes": 2
\\  }
\\}
;
const bad_field_src_father_id =
\\{
\\  "father_id": "daddy"
\\}
;
const bad_field_src_mother_id =
\\{
\\  "mother_id": "mommy"
\\}
;
const bad_field_src_mit_mother_id =
\\{
\\  "mitochondrial_mother_id": "meat mommy"
\\}
;
const bad_field_sources = [_][]const u8{
    bad_field_src_id,
    bad_field_src_name,
    bad_field_src_name_list,
    bad_field_src_surname,
    bad_field_src_surname_list,
    bad_field_src_date,
    bad_field_src_sex,
    bad_field_src_notes,
    bad_field_src_father_id,
    bad_field_src_mother_id,
    bad_field_src_mit_mother_id,
};
fn testAllocatorRequired(src: []const u8) !void {
    var parser = json.Parser.init(tator, false); // strings are copied in readFromJson
    defer parser.deinit();
    var tree = try parser.parse(src);
    defer tree.deinit();
    var hum = Person{.id=undefined};
    defer hum.deinit(tator);
    try expectError(anyerror.allocator_required, hum.readFromJson(&tree.root, null, .weak));
}
const allocator_required_src_name_list =
\\{
\\  "alternative_names": {}
\\}
;
const allocator_required_src_surname_list =
\\{
\\  "alternative_surnames": {}
\\}
;
const allocator_required_src_notes =
\\{
\\  "notes": {
\\    "child_nodes": {}
\\  }
\\}
;
const allocator_required_sources = [_][]const u8{
    allocator_required_src_name_list,
    allocator_required_src_surname_list,
    allocator_required_src_notes,
};
test "errors" {
    for (bad_type_sources) |bt_src| {
        try testError(bt_src, anyerror.bad_type);
    }
    for (bad_field_sources) |bf_src| {
        try testError(bf_src, anyerror.bad_field);
    }
    for (allocator_required_sources) |ar_src| {
        try testAllocatorRequired(ar_src);
    }
}



fn AOCheck(comptime allocator: ?Allocator, comptime options: StrMgmt) void {
    switch (options) {
        .copy => {
            if (null == allocator)
                @compileError("Person: can't copy w\\o allocator");
        },
        .move, .weak => {},
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
