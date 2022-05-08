const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const json = std.json;
const builtin = std.builtin;

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

pub fn AOCheck(allocator: anytype, comptime options: StrMgmt) void {
    switch (options) {
        .copy => {
            switch (@TypeOf(allocator)) {
                Allocator => {},
                @TypeOf(null) => @compileError("util: can't .copy w\\o allocator, did you mean .weak?"),
                else => @compileError("util: nonexhaustive switch in AOCheck()"),
            }
        },
        .move, .weak => {},
    }
}
pub fn allocatorCapture(allocator: anytype) ?Allocator {
    switch (@TypeOf(allocator)) {
        Allocator => return allocator,
        @TypeOf(null) => return null,
        else => @compileError("util: nonexhaustive switch in allocatorCapture()"),
    }
}
pub fn strCopyAlloc(from: []const u8, ator: Allocator) ![]u8 {
    var res = try ator.alloc(u8, from.len);
    for (from) |c, i| {
        res[i] = c;
    }
    return res;
}
pub fn strEqual(lhs: []const u8, rhs: []const u8) bool {
    if (lhs.len != rhs.len)
        return false;
    for (lhs) |c, i| {
        if (c != rhs[i])
            return false;
    }
    return true;
}

pub const MemoryError = error {
    OutOfMemory,
};
pub const ToJsonError = MemoryError;
pub const ToJsonSettings = struct {
    allow_overload: bool = true,
    apply_arena: bool = true,
};
pub const ToJsonResult = struct {
    value: json.Value,
    arena: ?ArenaAllocator = null,

    pub fn deinit(this: *ToJsonResult) void {
        if (this.arena) |*_arena| {
            _arena.deinit();
        }
    }
};

pub fn toJson(
    arg: anytype,
    ator: Allocator,
    comptime settings: ToJsonSettings,
) ToJsonError!ToJsonResult {
    const ArgType = @TypeOf(arg);
    var res = ToJsonResult{
        .value=undefined,
        .arena=null,
    };
    errdefer res.deinit();
    switch (@typeInfo(ArgType)) {
        .Optional => {
            if (arg) |value| {
                res = try toJson(value, ator, settings);
            } else {
                res.value = .{.Null={}};
            }
        },
        .Int => {
            if (ArgType != u64 and @sizeOf(ArgType) <= 8) {
                res.value = .{.Integer=@intCast(i64, arg)};
            } else {
                @compileError("can't turn " ++ @typeName(ArgType) ++ "into json.Integer");
            }
        },
        .Float => {
            if (ArgType != f128 and ArgType != c_longdouble) {
                res.value = .{.Float=@floatCast(f64, arg)};
            } else {
                @compileError("can't turn " ++ @typeName(ArgType) ++ "into json.Float");
            }
        },
        .Struct => {
            if (@hasDecl(ArgType, "toJson") and settings.allow_overload) {
                res = try arg.toJson(ator, settings);
            } else {
                res = try struct2json(
                    arg, ator,
                    .{
                        .allow_overload = true,
                        .apply_arena    = settings.apply_arena,
                    },
                );
            }
        },
        .Array => |array_info| {
            switch (array_info.child) {
                u8 => {
                    res.value = .{.String=arg};
                },
                else => {
                    res = try array2json(arg, ator, settings);
                },
            }
        },
        .Pointer => |pointer_info| {
            // TODO inspect pointer_info.size
            switch (pointer_info.child) {
                u8 => {
                    res.value = .{.String=arg};
                },
                else => {
                    res = try array2json(arg, ator, settings);
                },
            }
        },
        else => {
            @compileError("util.toJson(): don't know what to do w/ " ++ @typeName(ArgType));
        },
    }
    return res;
}

fn array2json(
    arg: anytype,
    _ator: Allocator,
    comptime settings: ToJsonSettings,
) ToJsonError!ToJsonResult {
    const ArgType = @TypeOf(arg);
    // TODO make 2 if's 1
    var res = ToJsonResult{
        .value = undefined,
        .arena = if (settings.apply_arena) ArenaAllocator.init(_ator) else null,
    };
    errdefer res.deinit();
    var ator = if (res.arena) |*arena| arena.allocator() else _ator;
    res.value = .{.Array=json.Array.init(ator)};
    const settings_to_pass = ToJsonSettings{
        .allow_overload = settings.allow_overload,
        .apply_arena    = false,
    };
    switch (@typeInfo(ArgType)) {
        .Array, .Pointer => {
            try res.value.Array.ensureUnusedCapacity(arg.len);
            for (arg) |item| {
                res.value.Array.appendAssumeCapacity(
                    (try toJson(item, ator, settings_to_pass)).value
                );
            }
        },
        else => {
            @compileError("util.array2jsonArr(): " ++ @typeName(ArgType) ++ " is not array");
        },
    }
    return res;
}

fn struct2json(
    arg: anytype,
    _ator: Allocator,
    comptime settings: ToJsonSettings,
) ToJsonError!ToJsonResult {
    const ArgType = @TypeOf(arg);
    // TODO make 2 if's 1
    var res = ToJsonResult{
        .value = undefined,
        .arena = if (settings.apply_arena) ArenaAllocator.init(_ator) else null,
    };
    errdefer res.deinit();
    const ator = if (res.arena) |*arena| arena.allocator() else _ator;
    res.value = .{.Object=json.ObjectMap.init(ator)};
    const settings_to_pass = ToJsonSettings{
        .allow_overload = settings.allow_overload, // must be true
        .apply_arena    = false,
    };
    switch (@typeInfo(ArgType)) {
        .Struct => |struct_info| {
            try res.value.Object.ensureUnusedCapacity(struct_info.fields.len);
            inline for (struct_info.fields) |field| {
                res.value.Object.putAssumeCapacityNoClobber(
                    field.name,
                    (try toJson(@field(arg, field.name), ator, settings_to_pass)).value,
                );
            }
        },
        else => {
            @compileError("util.struct2jsonObj(): " ++ @typeName(ArgType) ++ " is not struct");
        },
    }
    return res;
}

pub const EqualSettings = struct {
    allow_overload: bool = true,
};

pub fn equal(
    lhs: anytype,
    rhs: anytype,
    comptime settings: EqualSettings,
) bool {
    const ArgType = @TypeOf(lhs);
    switch (@typeInfo(ArgType)) {
        .Optional => {
            if (lhs) |lval| {
                if (rhs) |rval| {
                    return equal(lval, rval, .{.allow_overload=true});
                } else {
                    return false;
                }
            } else {
                if (rhs) |_| {
                    return false;
                } else {
                    return true;
                }
            }
        },
        .Int, .Float => {
            return lhs == rhs;
        },
        .Struct => |struct_info| {
            if (@hasDecl(ArgType, "equal") and settings.allow_overload) {
                return lhs.equal(rhs, .{.allow_overload=true});
            }
            inline for (struct_info.fields) |field| {
                const _lhs = @field(lhs, field.name);
                const _rhs = @field(rhs, field.name);
                if (!equal(_lhs, _rhs, .{.allow_overload=true})) {
                    std.debug.print("\n{s} field mismatch!\n", .{field.name});
                    // std.debug.print("\n{} != {}\n", .{_lhs, _rhs});
                    return false;
                }
            }
            return true;
        },
        .Array => {
            if (lhs.len != rhs.len) {
                return false;
            }
            for (lhs) |_lhs, i| {
                if (!equal(_lhs, rhs[i], settings)) {
                    return false;
                }
            }
            return true;
        },
        .Pointer => |pointer_info| {
            switch (pointer_info.size) {
                .Slice => {
                    if (lhs.len != rhs.len) {
                        return false;
                    }
                    for (lhs) |_lhs, i| {
                        if (!equal(_lhs, rhs[i], settings)) {
                            return false;
                        }
                    }
                    return true;
                },
                else => {
                    return lhs == rhs;
                },
            }
        },
        else => {
            @compileError("util.equal(): don't know what to do w/ " ++ @typeName(ArgType));
        },
    }
}

const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const tator = testing.allocator;

const Struct = struct {
    int: i64,
    float: f64,
    ss: SubStruct,

    const SubStruct = struct {
        int: i64,
        float: f64,
        pub fn toJson(self: SubStruct, ator: Allocator, comptime settings: ToJsonSettings) !ToJsonResult {
            _ = settings;
            var res = json.ObjectMap.init(ator);
            errdefer res.deinit();
            try res.put("int", @unionInit(json.Value, "Float", self.float));
            try res.put("float", @unionInit(json.Value, "Integer", self.int));
            return ToJsonResult{.value=.{.Object=res}, .arena=null};
        }
    };
};

const String = struct {
    data: []const u8,
};

test "to json" {
    var j_int = try toJson(@as(i64, 2), tator, .{});
    try expectEqual(j_int.value.Integer, 2);
    try expectEqual(j_int.arena, null);
    var j_float = try toJson(@as(f64, 2.0), tator, .{});
    try expectEqual(j_float.value.Float, 2.0);
    try expectEqual(j_float.arena, null);
    var s = Struct {
        .int = 1, .float = 1.0,
        .ss = .{
            .int = 2, .float = 2.0,
        },
    };
    var js = try toJson(s, tator, .{});
    defer js.deinit();
    _ = js;
    try expectEqual(js.value.Object.get("ss").?.Object.get("int").?.Float, 2.0);
    var o: ?i32 = 1;
    var oo: ?i32 = null;
    var j_o = try toJson(o, tator, .{});
    var j_oo = try toJson(oo, tator, .{});
    _ = j_o.value.Integer;
    _ = j_oo.value.Null;
    var string = String{.data = "string"};
    var j_string = try toJson(string, tator, .{});
    defer j_string.deinit();
    try expect(strEqual(string.data, j_string.value.Object.get("data").?.String));
}
