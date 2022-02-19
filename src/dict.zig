const std = @import("std");
const StringHashMap = std.StringHashMap;
const StringArrayHashMap = std.StringArrayHashMap;
const StringHashMapUnmanaged = std.StringHashMapUnmanaged;
const StringArrayHashMapUnmanaged = std.StringArrayHashMapUnmanaged;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

pub fn SlicePtrIterator(comptime T: type) type {
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

fn WarpedUnmanaged(comptime StdHashedUnmanaged: fn (type) type) fn (type) type {
// frees key-strings on deinit
return struct {
pub fn val_t(comptime V: type) type {
return struct {
    const Data = StdHashedUnmanaged(V);
    data: Data = .{},

    const Self = @This();
    const K = []const u8;
    const Size = switch (StdHashedUnmanaged) {
        StringHashMapUnmanaged => u32,
        StringArrayHashMapUnmanaged => usize,
        else => @compileError("WarpedUnmanaged.Size nonexhaustive switch on StdHashedUnmanaged"),
    };
    pub const Error = error { put_clobber, OutOfMemory, };
    pub fn deinit(this: *Self, ator: Allocator) void {
        var key_it = this.keyIterator();
        while (key_it.next()) |key_ptr| {
            ator.free(key_ptr.*);
        }
        this.data.deinit(ator);
    }
    pub const OperationOptions = struct {
        kopy: bool, // cOPY Keys
    };
    pub fn rawPut(
        this: *Self,
        key: K,
        val: V,
        ator: Allocator,
        options: OperationOptions,
    ) Error!void {
        if (options.kopy) {
            var copy = try strCopyAlloc(key, ator);
            errdefer ator.free(copy);
            try this.data.put(ator, copy, val);
        } else {
            try this.data.put(ator, key, val);
        }
    }
    pub fn rawPutAssumeCapacity(
        this: *Self,
        key: K,
        val: V,
        ator: Allocator,
        options: OperationOptions,
    ) Error!void {
        if (options.kopy) {
            var copy = try strCopyAlloc(key, ator);
            errdefer ator.free(copy);
            this.data.putAssumeCapacity(copy, val);
        } else {
            this.data.putAssumeCapacity(key, val);
        }
    }
    /// on ks == .copy key is not copied iff entry already exists!!!
    pub fn put(
        this: *Self,
        key: K,
        val: V,
        ator: Allocator,
        options: OperationOptions,
    ) Error!void {
        if (this.getEntry(key)) |entry| {
            if (options.kopy) {
                // const key_copy = try strCopyAlloc(key, ator);
                // ator.free(entry.key_ptr.*);
                // entry.key_ptr.* = key_copy;
                entry.value_ptr.* = val;
            } else {
                ator.free(entry.key_ptr.*);
                entry.key_ptr.* = key;
                entry.value_ptr.* = val;
            }
        } else {
            try this.rawPut(key, val, ator, options);
        }
    }
    pub fn putAssumeCapacity(
        this: *Self,
        key: K,
        val: V,
        ator: Allocator,
        options: OperationOptions,
    ) Error!void {
        if (this.getEntry(key)) |entry| {
            if (options.kopy) {
                // const key_copy = try strCopyAlloc(key, ator);
                // ator.free(entry.key_ptr.*);
                // entry.key_ptr.* = key_copy;
                entry.value_ptr.* = val;
            } else {
                ator.free(entry.key_ptr.*);
                entry.key_ptr.* = key;
                entry.value_ptr.* = val;
            }
        } else {
            try this.rawPutAssumeCapacity(key, val, ator, options);
        }
    }
    pub fn putNoClobber(
        this: *Self,
        key: K,
        val: V,
        ator: Allocator,
        options: OperationOptions,
    ) Error!void {
        if (this.contains(key)) {
            return Error.put_clobber;
        }
        try this.rawPut(key, val, ator, options);
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
    pub fn remove(this: *Self, key: K, ator: Allocator) bool {
        if (this.getKeyPtr(key)) |key_ptr| {
            const k = key_ptr.*; // not a single clue why this in needed, segfault otherwise
            switch (StdHashedUnmanaged) {
                StringHashMapUnmanaged => {
                    _ = this.data.remove(key);
                },
                StringArrayHashMapUnmanaged => {
                    _ = this.data.orderedRemove(key);
                },
                else => {
                    @compileError("WarpedUnmanaged.remove() nonexhaustive switch on StdHashedUnmanaged");
                },
            }
            ator.free(k);
            return true;
        }
        return false;
    }
    pub fn contains(this: *Self, key: K) bool {
        return this.data.contains(key);
    }
    pub fn clone(self: Self, ator: Allocator) Error!Self {
        var data_copy = try self.data.clone(ator);
        errdefer data_copy.deinit(ator);
        var key_copies_storage = ArrayListUnmanaged([]const u8){};
        defer key_copies_storage.deinit(ator);
        try key_copies_storage.ensureTotalCapacity(ator, self.data.count());
        errdefer {
            for (key_copies_storage.items) |item| {
                ator.free(item);
            }
        }
        var k_it = self.keyIterator();
        while (k_it.next()) |key_ptr| {
            var key_copy = try strCopyAlloc(key_ptr.*, ator);
            errdefer ator.free(key_copy);
            // try key_copies_storage.append(ator, key_copy);
            key_copies_storage.appendAssumeCapacity(key_copy);
            data_copy.getKeyPtr(key_ptr.*).?.* = key_copy;
        }
        return Self{.data=data_copy};
    }
    pub const clown = clone; // im the funniest
    pub fn move(this: *Self) Self {
        var res = Self{.data=this.data};
        this.* = Self{};
        return res;
    }
    pub fn swap(this: *Self, other: *Self) void {
        var swapper = other.move();
        other.* = this.*;
        this.* = swapper.move();
    }

    pub const Iterator = Data.Iterator;
    pub fn FieldIterator(comptime T: type) type {
        switch (StdHashedUnmanaged) {
            StringHashMapUnmanaged => {
                switch (T) {
                    K => {
                        return Data.KeyIterator;
                    },
                    V => {
                        return Data.ValueIterator;
                    },
                    else => {
                        @compileError("DictUnmanaged.FieldIterator(comptime) can only take K or V");
                    },
                }
                // return Data.FieldIterator(T);
            },
            StringArrayHashMapUnmanaged => {
                switch (T) {
                    K => {
                        return SlicePtrIterator(K);
                    },
                    V => {
                        return SlicePtrIterator(V);
                    },
                    else => {
                        @compileError("DictArrayUnmanaged.FieldIterator(comptime) can only take K or V");
                    },
                }
            },
            else => {
                @compileError("Warped.FieldIterator(comptime) nonexhaustive switch on StdHashedUnmanaged");
            },
        }
    }
    pub const KeyIterator = FieldIterator(K);
    pub const ValueIterator = FieldIterator(V);
    pub fn iterator(self: Self) Iterator {
        return self.data.iterator();
    }
    pub fn keyIterator(self: Self) KeyIterator {
        switch (StdHashedUnmanaged) {
            StringHashMapUnmanaged => {
                return self.data.keyIterator();
            },
            StringArrayHashMapUnmanaged => {
                return KeyIterator.init(self.data.keys());
            },
            else => {
                @compileError("Warped.keyIterator() nonexhaustive switch on stdHashed");
            },
        }
    }
    pub fn valueIterator(self: Self) ValueIterator {
        switch (StdHashedUnmanaged) {
            StringHashMapUnmanaged => {
                return self.data.valueIterator();
            },
            StringArrayHashMapUnmanaged => {
                return ValueIterator.init(self.data.values());
            },
            else => {
                @compileError("Warped.valueIterator() nonexhaustive switch on stdHashed");
            },
        }
    }
    pub fn count(self: Self) Size {
        return self.data.count();
    }
};
}
}.val_t;
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
    const Size = switch (StdHashed) {
        StringHashMap => u32,
        StringArrayHashMap => usize,
        else => @compileError("Warped.Size nonexhaustive switch on StdHashed"),
    };
    pub const Error = error { put_clobber, OutOfMemory, };
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
    pub const OperationOptions = struct {
        kopy: bool, // cOPY Keys
    };
    pub fn rawPut(
        this: *Self,
        key: K,
        val: V,
        options: OperationOptions,
    ) Error!void {
        if (options.kopy) {
            var copy = try strCopyAlloc(key, this.ator);
            errdefer this.ator.free(copy);
            try this.data.put(copy, val);
        } else {
            try this.data.put(key, val);
        }
    }
    pub fn rawPutAssumeCapacity(
        this: *Self,
        key: K,
        val: V,
        options: OperationOptions,
    ) Error!void {
        if (options.kopy) {
            var copy = try strCopyAlloc(key, this.ator);
            errdefer this.ator.free(copy);
            this.data.putAssumeCapacity(copy, val);
        } else {
            this.data.putAssumeCapacity(key, val);
        }
    }
    /// on ks == .copy key is not copied iff entry already exists!!!
    pub fn put(
        this: *Self,
        key: K,
        val: V,
        options: OperationOptions,
    ) Error!void {
        if (this.getEntry(key)) |entry| {
            if (options.kopy) {
                // const key_copy = try strCopyAlloc(key, this.ator);
                // this.ator.free(entry.key_ptr.*);
                // entry.key_ptr.* = key_copy;
                entry.value_ptr.* = val;
            } else {
                this.ator.free(entry.key_ptr.*);
                entry.key_ptr.* = key;
                entry.value_ptr.* = val;
            }
        } else {
            try this.rawPut(key, val, options);
        }
    }
    pub fn putAssumeCapacity(
        this: *Self,
        key: K,
        val: V,
        options: OperationOptions,
    ) Error!void {
        if (this.getEntry(key)) |entry| {
            if (options.kopy) {
                // const key_copy = try strCopyAlloc(key, this.ator);
                // this.ator.free(entry.key_ptr.*);
                // entry.key_ptr.* = key_copy;
                entry.value_ptr.* = val;
            } else {
                this.ator.free(entry.key_ptr.*);
                entry.key_ptr.* = key;
                entry.value_ptr.* = val;
            }
        } else {
            try this.rawPutAssumeCapacity(key, val, options);
        }
    }
    pub fn putNoClobber(
        this: *Self,
        key: K,
        val: V,
        options: OperationOptions,
    ) Error!void {
        if (this.contains(key)) {
            return Error.put_clobber;
        }
        try this.rawPut(key, val, options);
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
    pub fn clone(self: Self) Error!Self {
        var data_copy = try self.data.clone();
        errdefer data_copy.deinit();
        var key_copies_storage = ArrayList([]const u8).init(self.ator);
        defer key_copies_storage.deinit();
        try key_copies_storage.ensureTotalCapacity(self.data.count());
        errdefer {
            for (key_copies_storage.items) |item| {
                self.ator.free(item);
            }
        }
        var k_it = self.keyIterator();
        while (k_it.next()) |key_ptr| {
            var key_copy = try strCopyAlloc(key_ptr.*, self.ator);
            errdefer self.ator.free(key_copy);
            // try key_copies_storage.append(key_copy);
            key_copies_storage.appendAssumeCapacity(key_copy);
            data_copy.getKeyPtr(key_ptr.*).?.* = key_copy;
        }
        return Self{.data=data_copy, .ator=self.ator};
    }
    pub const clown = clone; // im the funniest
    pub fn move(this: *Self) Self {
        var res = Self{.data=this.data, .ator=this.ator};
        this.* = Self.init(this.ator);
        return res;
    }
    pub fn swap(this: *Self, other: *Self) void {
        if (this.ator.vtable != other.ator.vtable) unreachable;
        var swapper = other.move();
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
    pub fn iterator(self: Self) Iterator {
        return self.data.iterator();
    }
    pub fn keyIterator(self: Self) KeyIterator {
        switch (StdHashed) {
            StringHashMap => {
                return self.data.keyIterator();
            },
            StringArrayHashMap => {
                return KeyIterator.init(self.data.keys());
            },
            else => {
                @compileError("Warped.keyIterator() nonexhaustive switch on stdHashed");
            },
        }
    }
    pub fn valueIterator(self: Self) ValueIterator {
        switch (StdHashed) {
            StringHashMap => {
                return self.data.valueIterator();
            },
            StringArrayHashMap => {
                return ValueIterator.init(self.data.values());
            },
            else => {
                @compileError("Warped.valueIterator() nonexhaustive switch on stdHashed");
            },
        }
    }
    pub fn count(self: Self) Size {
        return self.data.count();
    }
};
}
}.val_t;
}

pub const DictUnmanaged = WarpedUnmanaged(StringHashMapUnmanaged);

pub const DictArrayUnmanaged = WarpedUnmanaged(StringArrayHashMapUnmanaged);

pub const Dict = Warped(StringHashMap);

pub const DictArray = Warped(StringArrayHashMap);


const testing = std.testing;
const expect = testing.expect;
const expectError = testing.expectError;
const tator = testing.allocator;

test "dict unmanaged" {
    var d = DictUnmanaged(i32){};
    defer d.deinit(tator);
    try d.put("osetr", 1, tator, .{.kopy=true});
    try expect(d.get("osetr").? == 1);
    var e_it = d.iterator();
    var unhandled_str = try strCopyAlloc("ahahahahaha", tator);
    // no defer free
    try d.put(unhandled_str, 2, tator, .{.kopy=false});
    try expectError(Dict(i32).Error.put_clobber, d.putNoClobber("osetr", 2, tator, .{.kopy=true}));
    try expect(d.remove("osetr", tator));
    try expect(!d.remove("osetr", tator));
    try d.put("osetr", 2, tator, .{.kopy=true});
    try d.put("osetr", 3, tator, .{.kopy=true});
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
    var c = try d.clown(tator);
    defer c.deinit(tator);
    try expect(c.get("osetr").? == 4);
    var cc = try c.clown(tator);
    // no defer deinit
    var m = cc.move();
    defer m.deinit(tator);
    var s = DictUnmanaged(i32){};
    defer s.deinit(tator);
    var ccc = try c.clown(tator);
    // no defer deinit
    s.swap(&ccc);
    try expect(ccc.data.count() == 0);
    try expect(s.get("osetr").? == 4);
}

test "dict array unmanaged" {
    var d = DictArrayUnmanaged(i32){};
    defer d.deinit(tator);
    try d.put("osetr", 1, tator, .{.kopy=true});
    try expect(d.get("osetr").? == 1);
    var e_it = d.iterator();
    var unhandled_str = try strCopyAlloc("ahahahahaha", tator);
    // no defer free
    try d.put(unhandled_str, 2, tator, .{.kopy=false});
    try expectError(Dict(i32).Error.put_clobber, d.putNoClobber("osetr", 2, tator, .{.kopy=true}));
    try expect(d.remove("osetr", tator));
    try expect(!d.remove("osetr", tator));
    try d.put("osetr", 2, tator, .{.kopy=true});
    try d.put("osetr", 3, tator, .{.kopy=true});
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
    var c = try d.clown(tator);
    defer c.deinit(tator);
    try expect(c.get("osetr").? == 4);
    var cc = try c.clown(tator);
    // no defer deinit
    var m = cc.move();
    defer m.deinit(tator);
    var s = DictArrayUnmanaged(i32){};
    defer s.deinit(tator);
    var ccc = try c.clown(tator);
    // no defer deinit
    s.swap(&ccc);
    try expect(ccc.data.count() == 0);
    try expect(s.get("osetr").? == 4);
}

test "dict" {
    var d = Dict(i32).init(tator);
    defer d.deinit();
    try d.put("osetr", 1, .{.kopy=true});
    try expect(d.get("osetr").? == 1);
    var e_it = d.iterator();
    var unhandled_str = try strCopyAlloc("ahahahahaha", tator);
    // no defer free
    try d.put(unhandled_str, 2, .{.kopy=false});
    try expectError(Dict(i32).Error.put_clobber, d.putNoClobber("osetr", 2, .{.kopy=true}));
    try expect(d.remove("osetr"));
    try expect(!d.remove("osetr"));
    try d.put("osetr", 2, .{.kopy=true});
    try d.put("osetr", 3, .{.kopy=true});
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
    var cc = try c.clown();
    // no defer deinit
    var m = cc.move();
    defer m.deinit();
    var s = Dict(i32).init(tator);
    defer s.deinit();
    var ccc = try c.clown();
    // no defer deinit
    s.swap(&ccc);
    try expect(ccc.data.count() == 0);
    try expect(s.get("osetr").? == 4);
}

test "dict array" {
    var d = DictArray(i32).init(tator);
    defer d.deinit();
    try d.put("osetr", 1, .{.kopy=true});
    try expect(d.get("osetr").? == 1);
    var e_it = d.iterator();
    var unhandled_str = try strCopyAlloc("ahahahahaha", tator);
    // no defer free
    try d.put(unhandled_str, 2, .{.kopy=false});
    try expectError(Dict(i32).Error.put_clobber, d.putNoClobber("osetr", 2, .{.kopy=true}));
    try expect(d.remove("osetr"));
    try expect(!d.remove("osetr"));
    try d.put("osetr", 2, .{.kopy=true});
    try d.put("osetr", 3, .{.kopy=true});
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

