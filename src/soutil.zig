const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const json = std.json;

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
                res = toJson(value, ator, settings);
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
                res = arg.toJson(ator, settings);
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
                    try toJson(item, ator, settings_to_pass)
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
    var ator = if (res.arena) |*arena| arena.allocator() else _ator;
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

pub const JsonTag = enum {
    Null, Bool, Integer, Float, NumberString, String, Array, Object,

    pub fn asText(comptime tag: JsonTag) switch (tag) {
        .Null => @TypeOf("Null"),
        .Bool => @TypeOf("Bool"),
        .Integer => @TypeOf("Integer"),
        .Float => @TypeOf("Float"),
        .NumberString => @TypeOf("NumberString"),
        .String => @TypeOf("String"),
        .Array => @TypeOf("Array"),
        .Object => @TypeOf("Object"),
    } {
        return switch (tag) {
            .Null => "Null",
            .Bool => "Bool",
            .Integer => "Integer",
            .Float => "Float",
            .NumberString => "NumberString",
            .String => "String",
            .Array => "Array",
            .Object => "Object",
        };
    }
};
pub fn type2jtag (comptime t: type) JsonTag {
    switch (@typeInfo(t)) {
        .Optional => |optional| {
            // @compileLog(@typeName(t));
            return type2jtag(optional.child);
        },
        .Int => {
            if (t != u64 and @sizeOf(t) <= 8) {
                return .Integer;
            } else {
                @compileError("util.type2jtag(): can't work with " ++ @typeName(t));
            }
        },
        .Float => {
            if (@sizeOf(t) <= 8) {
                return .Float;
            } else {
                @compileError("util.type2jtag(): can't work with " ++ @typeName(t));
            }
        },
        else => {
            return switch (t) {
                // i64 => .Integer, // already handled
                // f64 => .Float, // already handled
                void => .Null,
                bool => .Bool,
                []const u8 => .String,
                json.Array => .Array,
                json.ObjectMap => .Object,
                else => {
                    @compileError("util.type2jtag(): can't infer json tag from " ++ @typeName(t));
                },
            };
        },
    }
}

const String = struct {
    data: []const u8,
};

const testing = std.testing;
const expect = testing.expect;
const tator = testing.allocator;

test "" {
    // var j_int = try toJson(@as(i64, 2), tator, .{});
    // switch (j_int.value) {
    //     .Integer => {
    //         std.debug.print("\nInteger!!!\n", .{});
    //     },
    //     .Float => {
    //         std.debug.print("\nFloat!!!\n", .{});
    //     },
    //     else => {
    //         std.debug.print("\nelse!!!\n", .{});
    //     },
    // }
    // try expect(j_int.value.Integer == 2);
    var string = String{.data = "string"};
    var j_string = try toJson(string, tator, .{});
    defer j_string.deinit();
    try expect(strEqual(string.data, j_string.value.Object.get("data").?.String));
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
