const std = @import("std");
const json = std.json;
const mem = std.mem;
const Allocator = mem.Allocator;
const dict_module = @import("dict.zig");
const DictArrayUnmanaged = dict_module.DictArrayUnmanaged;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const logger = std.log.scoped(.ft);


// probably only StrMgmt.copy should ever be used
pub const StrMgmt = enum {
    copy, move, weak,

    pub fn asText(
        comptime options: StrMgmt
    ) switch (options) {
        .copy => @TypeOf("copy"),
        .move => @TypeOf("move"),
        .weak => @TypeOf("move"),
    } {
        return switch (options) {
            .copy => "copy",
            .move => "move",
            .weak => "weak",
        };
    }
};


pub const Notes = struct {
    /// comptime interfaces: [ deinit, readFromJson, clone/swap/move, ]
    text: []const u8 = "",
    child_nodes: DictArrayUnmanaged(Notes) = .{},
    depth: u8 = 0,

    const max_depth = 255;

    pub const FromJsonError = error {
        bad_type,           bad_field,
        allocator_required, max_depth_reached,
    };
    pub const Error = FromJsonError||DictArrayUnmanaged(Notes).Error;
    pub fn deinit(this: *Notes, ator: Allocator) void {
        logger.debug("Notes.deinit() w/ depth={d}, ator={*}", .{this.depth, ator.vtable});
        ator.free(this.text);
        this.deinitChildNodes(ator);
    }
    pub fn deinitChildNodes(this: *Notes, ator: Allocator) void {
        logger.debug("Notes.deinitChildNotes() w/ depth={d}, ator={*}", .{this.depth, ator.vtable});
        // var val_it = this.child_nodes.data.valueIterator();
        // while (val_it.next()) |val_ptr| {
        //     val_ptr.deinit(ator);
        // }
        for (this.child_nodes.data.values()) |*val| {
            val.deinit(ator);
        }
        this.child_nodes.deinit(ator); // child_nodes keys are freed here
    }

    pub fn readFromJson(
        this: *Notes,
        json_notes: *json.Value,
        comptime allocator: ?Allocator,
        comptime options: StrMgmt,
    ) Error!void {
        AOCheck(allocator, options);
        logger.debug("Notes.readFromJson() w/ depth={d}, options={s}", .{this.depth, options.asText()});
        switch (json_notes.*) {
            json.Value.Object => |map| {
                inline for (@typeInfo(Notes).Struct.fields) |field| {
                    if (map.get(field.name)) |*val| {
                        switch (field.field_type) {
                            u8 => {
                                logger.warn("in Logger.warn() found \"{s}\" field", .{field.name});
                            },
                            []const u8 => {
                                switch (val.*) {
                                    json.Value.String, json.Value.NumberString => {
                                        try this.readFromJson(val, allocator, options);
                                    },
                                    else => {
                                        logger.err(
                                            "in Notes.readFromJson()" ++
                                            " j_notes.get(\"text\")" ++
                                            " is not of type {s}"
                                            , .{"json.String"}
                                        );
                                        return FromJsonError.bad_field;
                                    },
                                }
                            },
                            DictArrayUnmanaged(Notes) => {
                                if (allocator) |ator| {
                                    switch (val.*) {
                                        json.Value.Object => |*nmap| {
                                            this.child_nodes = try dictArrayFromJsonObj(
                                                nmap, ator, options, this.depth
                                            );
                                        },
                                        else => {
                                            logger.err(
                                                "in Notes.readFromJson()" ++
                                                " j_notes.get(\"child_nodes\")" ++
                                                " is not of type {s}"
                                                , .{"json.ObjectMap"}
                                            );
                                            return FromJsonError.bad_field;
                                        },
                                    }
                                } else {
                                    logger.err(
                                        \\in Notes.readFromJson()
                                        \\ allocator required
                                        , .{}
                                    );
                                    return FromJsonError.allocator_required;
                                }
                            },
                            else => {
                                @compileError("Notes.readFromJson() nonexhaustive switch on field_type");
                            },
                        }
                    }
                }
            },
            json.Value.String, json.Value.NumberString => |*str| {
                switch (options) {
                    .copy => {
                        if (allocator) |ator| {
                            this.text = try strCopyAlloc(str.*, ator);
                        } else {
                            unreachable; // AOCheck()
                        }
                    },
                    .move => {
                        this.text = str.*;
                        str.* = "";
                    },
                    .weak => {
                        this.text = str.*;
                    },
                }
            },
            else => {
                logger.err(
                    "in Notes.readFromJson() j_notes is of neither type" ++
                    " {s} nor {s}"
                    , .{"json.ObjectMap", "json.String"}
                );
                return FromJsonError.bad_type;
            },
        }
    }
    fn dictArrayFromJsonObj(
        obj: *json.ObjectMap,
        comptime ator: Allocator,
        comptime options: StrMgmt,
        depth: u8,
    ) Error!DictArrayUnmanaged(Notes) {
        logger.debug("Notes.dectArrayFromJsonObj() on depth={d}", .{depth});
        if (max_depth == depth) {
            logger.err(
                \\in Notes.readFromJson() max depth reached
                , .{}
            );
            return FromJsonError.max_depth_reached;
        }
        var res = DictArrayUnmanaged(Notes){};
        errdefer {
            var val_it = res.valueIterator();
            while (val_it.next()) |val_ptr| {
                val_ptr.deinit(ator);
            }
            res.deinit(ator);
        }
        var j_it = obj.iterator();
        while (j_it.next()) |entry| {
            if (res.contains(entry.key_ptr.*)) {
                logger.warn(
                    \\in Notes.readFromJson() repeated key '{s}' in j_note_dict
                    \\ skipping...
                    , .{entry.key_ptr.*}
                );
            } else {
                var notes = Notes{};
                errdefer notes.deinit(ator);
                notes.depth = depth + 1;
                try notes.readFromJson(entry.value_ptr, ator, options);
                switch (options) {
                    .copy => {
                        try res.putNoClobber(entry.key_ptr.*, notes, ator, .{.kopy=true});
                    },
                    .move => {
                        try res.putNoClobber(entry.key_ptr.*, notes, ator, .{.kopy=false});
                        entry.key_ptr.* = "";
                    },
                    .weak => {
                        try res.putNoClobber(entry.key_ptr.*, notes, ator, .{.kopy=false});
                    },
                }
            }
        }
        return res;
    }

    pub fn clone(self: Notes, ator: Allocator) !Notes {
        logger.debug("Notes.clone() w/ ator={*}", .{ator.vtable});
        var copy = Notes{};
        errdefer copy.deinit(ator);
        copy.depth = self.depth;
        copy.text = try strCopyAlloc(self.text, ator);
        // errdefer copy.deinit() handles copy.text deallocation
        var s_it = self.data.iterator();
        while (s_it.next()) |s_entry| {
            var copy_label = try strCopyAlloc(s_entry.key_ptr.*);
            errdefer copy.ator.free(copy_label);
            var copy_notes = try s_entry.value_ptr.copy();
            errdefer copy_notes.deinit();
            try copy.data.putNoClobber(copy_label, copy_notes, .move);
        }
        return copy;
    }
    pub fn swap(this: *Notes, other: *Notes) void {
        logger.debug("Notes.swap()", .{});
        var swapper = other.move();
        other.* = this.*;
        this.* = swapper.move();
    }
    pub fn move(this: *Notes) Notes {
        logger.debug("Notes.move()", .{});
        var res = Notes{.text = this.text, .child_nodes = this.child_nodes};
        this.* = Notes{};
        return res;
    }
    fn AOCheck(comptime allocator: ?Allocator, comptime options: StrMgmt) void {
        switch (options) {
            .copy => if (null == allocator)
                @compileError("Notes: can't .copy strings w\\o allocator, did you mean .weak?"),
            .move, .weak => {},
        }
    }
};

const testing = std.testing;
const expect = testing.expect;
const expectError = testing.expectError;
const tator = testing.allocator;

const simple_text_source =
\\"simple text"
;
const nested_1_source =
\\{
\\  "text": "depth 0",
\\  "child_nodes": {
\\    "node1": "simple dimple"
\\  }
\\}
;
const nested_2_source =
\\{
\\  "text": "depth 0",
\\  "child_nodes": {
\\    "node1": {
\\      "text": "depth 1",
\\      "child_nodes": {
\\          "node2": "pop it"
\\      }
\\    }
\\  }
\\}
;

fn testBasicAnswers(notes: *Notes) !void {
    if (notes.child_nodes.count() == 0) {
        try expect(strEqual("simple text", notes.text));
    } else {
        try expect(strEqual("depth 0", notes.text));
        if (notes.child_nodes.get("node1")) |*node1| {
            try expect(strEqual("simple dimple", node1.text) or strEqual("depth 1", node1.text));
            if (node1.child_nodes.get("node2")) |*node2| {
                try expect(strEqual("pop it", node2.text));
            }
        } else {
            unreachable;
        }
    }
}
fn testBasic(src: []const u8, comptime options: StrMgmt) !void {
    var parser = json.Parser.init(tator, false);
    defer parser.deinit();
    var tree = try parser.parse(src);
    defer tree.deinit();
    var notes = Notes{};
    try notes.readFromJson(&tree.root, tator, options);
    try testBasicAnswers(&notes);
    switch (options) {
        .copy => {
            defer notes.deinit(tator);
        },
        .weak, .move => {
            defer notes.child_nodes.data.deinit(tator);
            defer {
                if (notes.child_nodes.count() > 0) {
                    var n_it = notes.child_nodes.iterator();
                    while (n_it.next()) |node_entry| {
                        node_entry.value_ptr.child_nodes.data.deinit(tator);
                    }
                }
            }
            defer {
                if (notes.child_nodes.count() > 0) {
                    var n_it = notes.child_nodes.iterator();
                    while (n_it.next()) |node_entry| {
                        if (node_entry.value_ptr.child_nodes.count() > 0) {
                            var nn_it = node_entry.value_ptr.child_nodes.iterator();
                            while (nn_it.next()) |nnode_entry| {
                                nnode_entry.value_ptr.child_nodes.data.deinit(tator);
                            }
                        }
                    }
                }
            }
        },
    }
}
test "basic" {
    try testBasic(simple_text_source, .copy);
    try testBasic(simple_text_source, .move);
    try testBasic(simple_text_source, .weak);
    try testBasic(nested_1_source, .copy);
    try testBasic(nested_1_source, .move);
    try testBasic(nested_1_source, .weak);
    try testBasic(nested_2_source, .copy);
    try testBasic(nested_2_source, .move);
    try testBasic(nested_2_source, .weak);
}

const bad_type_0_source =
\\1
;
const bad_type_1_source =
\\{"child_nodes": {"node": 1}}
;
const bad_field_0_source =
\\{"text": 1}
;
const bad_field_1_source =
\\{"text": "simple text", "child_nodes": 1}
;

fn testError(eerr: anyerror, src: []const u8) !void {
    var parser = json.Parser.init(tator, false);
    defer parser.deinit();
    var tree = try parser.parse(src);
    defer tree.deinit();
    var notes = Notes{};
    defer notes.deinit(tator);
    try expectError(eerr, notes.readFromJson(&tree.root, tator, .copy));
}

test "errors" {
    try testError(Notes.FromJsonError.bad_type, bad_type_0_source);
    try testError(Notes.FromJsonError.bad_type, bad_type_1_source);
    try testError(Notes.FromJsonError.bad_field, bad_field_0_source);
    try testError(Notes.FromJsonError.bad_field, bad_field_1_source);
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

