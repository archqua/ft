const std = @import("std");
const StringHashMap = std.StringHashMap;
const StringArrayHashMap = std.StringArrayHashMap;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

fn SlicePtrIterator(comptime T: type) type {
return struct {
    slice: []T,
    pub fn init(sl: []T) @This() {
        return @This(){.slice=sl};
    }
    pub fn next(this: *@This()) ?*T {
        if (this.slice.len > 0) {
            defer this.slice = this.slice[1..];
            return &this.slice[0];
        } else {
            return null;
        }
    }
};
}

fn Warped(comptime StdHashed: fn (type) type) fn (type) type {
// frees key-strings on deinit
return struct {
pub fn val_t(comptime V: type) type {
return struct {
    const Data = StdHashed(V);
    data: Data,
    ator: Allocator,

    const Self = @This();
    const K = []const u8;
    pub const Error = error { put_clobber, };
    pub fn init(ator: Allocator) Self {
        return Self{.data=Data.init(ator), .ator=ator};
    }
    pub fn deinit(this: *Self) void {
        var key_it = this.keyIterator();
        while (key_it.next()) |key_ptr| {
            this.ator.free(key_ptr.*);
        }
        this.data.deinit();
    }
    pub const KeyBehaviour = enum { clone, move, };
    pub fn rawPut(this: *Self, key: K, val: V, kb: KeyBehaviour) !void {
        switch (kb) {
            .clone => {
                var copy = try strCopyAlloc(key, this.ator);
                errdefer this.ator.free(copy);
                try this.data.put(copy, val);
            },
            .move => {
                try this.data.put(key, val);
            },
        }
    }
    pub fn put(this: *Self, key: K, val: V, kb: KeyBehaviour) !void {
        _ = this.remove(key); // safe since checks are done inside remove
        try this.rawPut(key, val, kb);
    }
    pub fn putNoClobber(this: *Self, key: K, val: V, kb: KeyBehaviour) !void {
        if (this.contains(key)) {
            return Error.put_clobber;
        }
        try this.rawPut(key, val, kb);
    }
    pub fn get(this: *Self, key: K) ?V {
        return this.data.get(key);
    }
    pub fn getPtr(this: *Self, key: K) ?*V {
        return this.data.getPtr(key);
    }
    pub fn getKey(this: *Self, key: K) ?K {
        return this.data.getKey(key);
    }
    pub fn getKeyPtr(this: *Self, key: K) ?*K {
        return this.data.getKeyPtr(key);
    }
    pub const Entry = Data.Entry;
    pub fn getEntry(this: *Self, key: K) ?Entry {
        return this.data.getEntry(key);
    }
    pub fn remove(this: *Self, key: K) bool {
        if (this.getKeyPtr(key)) |key_ptr| {
            const k = key_ptr.*; // not a single clue why this in needed, segfault otherwise
            switch (StdHashed) {
                StringHashMap => {
                    _ = this.data.remove(key);
                },
                StringArrayHashMap => {
                    _ = this.data.orderedRemove(key);
                },
                else => {
                    @compileError("Warped.remove() nonexhaustive switch on StdHashed");
                },
            }
            this.ator.free(k);
            return true;
        }
        return false;
    }
    pub fn contains(this: *Self, key: K) bool {
        return this.data.contains(key);
    }
    pub fn clone(this: Self) !Self {
        var data_copy = try this.data.clone();
        errdefer data_copy.deinit();
        var key_copies_storage = ArrayList([]const u8).init(this.ator);
        defer key_copies_storage.deinit();
        errdefer {
            for (key_copies_storage.items) |item| {
                this.ator.free(item);
            }
        }
        var k_it = this.keyIterator();
        while (k_it.next()) |key_ptr| {
            var key_copy = try strCopyAlloc(key_ptr.*, this.ator);
            errdefer this.ator.free(key_copy);
            try key_copies_storage.append(key_copy);
            data_copy.getKeyPtr(key_ptr.*).?.* = key_copy;
        }
        return Self{.data=data_copy, .ator=this.ator};
    }
    pub const clown = clone; // im the funniest
    pub fn move(this: *Self) Self {
        var res = Self{.data=this.data, .ator=this.ator};
        this.data = Data.init(this.ator);
        return res;
    }
    pub fn swap(this: *Self, other: *Self) void {
        var swapper = other.move();
        defer swapper.deinit();
        other.* = this.*;
        this.* = swapper.move();
    }

    pub const Iterator = Data.Iterator;
    pub fn FieldIterator(comptime T: type) type {
        switch (StdHashed) {
            StringHashMap => {
                switch (T) {
                    K => {
                        return Data.KeyIterator;
                    },
                    V => {
                        return Data.ValueIterator;
                    },
                    else => {
                        @compileError("Dict.FieldIterator(comptime) can only take K or V");
                    },
                }
                // return Data.FieldIterator(T);
            },
            StringArrayHashMap => {
                switch (T) {
                    K => {
                        return SlicePtrIterator(K);
                    },
                    V => {
                        return SlicePtrIterator(V);
                    },
                    else => {
                        @compileError("DictArray.FieldIterator(comptime) can only take K or V");
                    },
                }
            },
            else => {
                @compileError("Warped.FieldIterator(comptime) nonexhaustive switch on StdHashed");
            },
        }
    }
    pub const KeyIterator = FieldIterator(K);
    pub const ValueIterator = FieldIterator(V);
    pub fn iterator(this: *Self) Iterator {
        return this.data.iterator();
    }
    pub fn keyIterator(this: *const Self) KeyIterator {
        switch (StdHashed) {
            StringHashMap => {
                return this.data.keyIterator();
            },
            StringArrayHashMap => {
                return KeyIterator.init(this.data.keys());
            },
            else => {
                @compileError("Warped.keyIterator() nonexhaustive switch on stdHashed");
            },
        }
    }
    pub fn valueIterator(this: *const Self) ValueIterator {
        switch (StdHashed) {
            StringHashMap => {
                return this.data.valueIterator();
            },
            StringArrayHashMap => {
                return ValueIterator.init(this.data.values());
            },
            else => {
                @compileError("Warped.valueIterator() nonexhaustive switch on stdHashed");
            },
        }
    }
};
}
}.val_t;
}

pub const Dict = Warped(StringHashMap);

pub const DictArray = Warped(StringArrayHashMap);


const testing = std.testing;
const expect = testing.expect;
const expectError = testing.expectError;
const tator = testing.allocator;

test "dict" {
    var d = Dict(i32).init(tator);
    defer d.deinit();
    try d.put("osetr", 1, .clone);
    try expect(d.get("osetr").? == 1);
    var e_it = d.iterator();
    var unhandled_str = try strCopyAlloc("ahahahahaha", tator);
    try d.put(unhandled_str, 2, .move);
    try expectError(Dict(i32).Error.put_clobber, d.putNoClobber("osetr", 2, .clone));
    try expect(d.remove("osetr"));
    try expect(!d.remove("osetr"));
    try d.put("osetr", 2, .clone);
    try d.put("osetr", 3, .clone);
    try expect(d.get("osetr").? == 3);
    try expect(d.get(unhandled_str).? == 2);
    d.getPtr("osetr").?.* = 4;
    try expect(d.get("osetr").? == 4);
    while (e_it.next()) |entry| {
        try expect(@TypeOf(entry.key_ptr.*) == []const u8);
        try expect(@TypeOf(entry.value_ptr.*) == i32);
    }
    var v_it = d.valueIterator();
    while (v_it.next()) |v_ptr| {
        try expect(@TypeOf(v_ptr.*) == i32);
    }
    var k_it = d.keyIterator();
    while (k_it.next()) |k_ptr| {
        try expect(@TypeOf(k_ptr.*) == []const u8);
    }
    var c = try d.clown();
    defer c.deinit();
    try expect(c.get("osetr").? == 4);
}

test "dict array" {
    var d = DictArray(i32).init(tator);
    defer d.deinit();
    try d.put("osetr", 1, .clone);
    try expect(d.get("osetr").? == 1);
    var e_it = d.iterator();
    var unhandled_str = try strCopyAlloc("ahahahahaha", tator);
    try d.put(unhandled_str, 2, .move);
    try expectError(Dict(i32).Error.put_clobber, d.putNoClobber("osetr", 2, .clone));
    try expect(d.remove("osetr"));
    try expect(!d.remove("osetr"));
    try d.put("osetr", 2, .clone);
    try d.put("osetr", 3, .clone);
    try expect(d.get("osetr").? == 3);
    try expect(d.get(unhandled_str).? == 2);
    d.getPtr("osetr").?.* = 4;
    try expect(d.get("osetr").? == 4);
    while (e_it.next()) |entry| {
        try expect(@TypeOf(entry.key_ptr.*) == []const u8);
        try expect(@TypeOf(entry.value_ptr.*) == i32);
    }
    var v_it = d.valueIterator();
    while (v_it.next()) |v_ptr| {
        try expect(@TypeOf(v_ptr.*) == i32);
    }
    var k_it = d.keyIterator();
    while (k_it.next()) |k_ptr| {
        try expect(@TypeOf(k_ptr.*) == []const u8);
    }
    var c = try d.clown();
    defer c.deinit();
    try expect(c.get("osetr").? == 4);
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

