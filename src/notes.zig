const std = @import(std);
const json = std.json;
const Allocator = std.mem.Allocator;
const dict_module = @import("dict.zig");
const DictArray = dict_module.DictArray;
const testing = std.testing;
const expect = std.expect;

pub const Notes = struct {
    /// comptime interfaces: [ init/deinit, readFromJson, clone/swap/move, ]
    text: []const u8 = "",
    child_nodes: DictArray(Notes),
    ator: Allocator,

    pub const FromJsonError = error { bad_type, bad_field, };
    pub fn init(ator: Allocator) Notes {
        return Notes{
            .child_notes = DictArray(Notes).init(ator),
            .ator = ator,
        };
    }
    pub fn deinit(this: *Notes) void {
        this.ator.free(text);
        this.deinitChildNodes();
    }
    pub fn deinitChildNodes(this: *Notes) void {
        var val_it = this.child_nodes.data.valueIterator();
        while (val_it.next()) |val_ptr| {
            val_ptr.deinit();
        }
        this.child_nodes.deinit(); // child_nodes keys are freed here
    }

    pub fn readFromJson(
        this: *Notes,
        json_notes: json.Value,
    ) !void {
        switch (json_notes) {
            json.Value.Object => |map| {
                inline for (@typeInfo(Notes).Struct.fields) |field| {
                    switch (field.field_type) {
                        Allocator => {},
                        []const u8 => {
                            if (map.get("text")) |str| {
                                try this.readFromJson(str);
                            }
                        },
                        DictArray(Notes) => |omap| {
                            if (map.get("child_nodes")) {
                                var copy = try dictArrayFromJsonObj(omap);
                                this.deinitChildNodes();
                                this.child_nodes = copy;
                            }
                        },
                        else => { @compileError("nonexhaustive switch on field type in Notes.readFromJson()"); },
                    }
                }
            },
            json.Value.String, json.Value.NumberString => |str| {
                var copy = try strCopyAlloc(str, this.ator);
                this.ator.free(this.text);
                this.text = copy;
            },
            else => { return FromJsonError.bad_type; },
        }
    }
    fn dictArrayFromJsonObj(
        obj: json.ObjectMap, ator: Allocator
    ) !StringArrayHashMap(Notes) {
        var res = StringArrayHashMap(Notes).init(ator);
        errdefer {
            var val_it = res.valueIterator();
            while (val_it.next()) |val_ptr| {
                val_ptr.deinit();
            }
            res.deinit();
        };
        var iter = obj.iterator();
        while (iter.next()) |entry| {
            switch (entry.value_ptr.*) {
                json.Value.Object => |map| {
                    //
                },
                json.String, json.NumberString => |str| {
                    //
                },
                else => { return FromJsonError.bad_type; }
            }
        }
    }

    pub fn clone(self: Notes) !Notes; // TODO
    pub fn swap(this: *Notes, other: *Notes); // TODO
    pub fn move(this: *Notes) Notes; // TODO
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

