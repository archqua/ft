const std = @import("std");
const person_module = @import("person.zig");
const family_module = @import("family.zig");
const json = std.json;
const util = @import("util.zig");


const Person = person_module.Person;
const Family = family_module.Family;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Prng = std.rand.DefaultPrng;
const AutoHashMapUnmanaged = std.AutoHashMapUnmanaged;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const logger = std.log.scoped(.ft);



const FamilyTree = struct {
    ator: Allocator,
    rand: Prng,
    pk2person_info: AutoHashMapUnmanaged(PersonKey, PersonInfo) = .{},
    fk2family: AutoHashMapUnmanaged(FamilyKey, Family) = .{},
    
    pub const person_unregistered = @as(Person.Id, -1);
    pub const family_unregistered = @as(Family.Id, -1);
    pub const person_invalidated = @as(Person.Id, -2);
    pub const family_invalidated = @as(Family.Id, -2);
    pub const max_pid = switch (@typeInfo(Person.Id).Int.signedness) {
        .signed => ~@bitReverse(Person.Id, 1),
        .unsigned => @compileError("wrong understanding of Person.Id as signed int"),
    };
    pub const min_pid = @as(Person.Id, 0);
    pub const max_fid = switch (@typeInfo(Family.Id).Int.signedness) {
        .signed => ~@bitReverse(Family.Id, 1),
        .unsigned => @compileError("wrong understanding of Family.Id as signed int"),
    };
    pub const min_fid = @as(Family.Id, 0);
    pub const max_pkgen_iter = ~@as(u8, 0);
    pub const max_fkgen_iter = ~@as(u8, 0);

    pub const PersonKey = switch (Person.Id == i64) {
        true => u32,
        false => @compileError("wrong understanding of Person.Id as i64"),
    };
    pub const FamilyKey = switch (Family.Id == i64) {
        true => u32,
        false => @compileError("wrong understanding of Family.Id as i64"),
    };
    
    pub const PersonInfo = struct {
        person: Person,
        fo_connections: FOConnections = .{},

        pub const FOConnections = struct {
            // blood
            father_key: ?PersonKey = null,
            mother_key: ?PersonKey = null,
            mit_mother_key: ?PersonKey = null,
            children: ArrayListUnmanaged(PersonKey) = .{},
            // social
            families: ArrayListUnmanaged(FamilyKey) = .{},
            pub fn deinit(this: *FOConnections, ator: Allocator) void {
                this.families.deinit(ator);
                this.children.deinit(ator);
            }
            pub fn hasChild(self: FOConnections, candidate: PersonKey) bool {
                for (self.children.items) |child_key| {
                    if (child_key == candidate)
                        return true;
                }
                return false;
            }
            pub fn hasFamily(self: FOConnections, candidate: FamilyKey) bool {
                for (self.families.items) |family_key| {
                    if (family_key == candidate)
                        return true;
                }
                return false;
            }
            pub fn addChild(this: *FOConnections, child: PersonKey, ator: Allocator) !bool {
                if (!this.hasChild(child)) {
                    try this.children.append(ator, child);
                    return true;
                }
                return false;
            }
            pub fn addFamily(this: *FOConnections, family: FamilyKey, ator: Allocator) !bool {
                if (!this.hasFamily(family)) {
                    try this.families.append(ator, family);
                    return true;
                }
                return false;
            }
            pub const ParentEnum = enum {
                father, mother, mit_mother,
                pub fn asText(comptime self: ParentEnum) switch (self) {
                    .father => @TypeOf("father"),
                    .mother => @TypeOf("mother"),
                    .mit_mother => @TypeOf("mit_mother"),
                } {
                    return switch (self) {
                        .father => "father",
                        .mother => "mother",
                        .mit_mother => "mit_mother",
                    };
                }
            };
            pub const ListConnEnum = enum {
                children, families,
                pub fn asText(comptime self: ListConnEnum) switch (self) {
                    .children => @TypeOf("children"),
                    .families => @TypeOf("families"),
                } {
                    return switch (self) {
                        .children => "children",
                        .families => "families",
                    };
                }
            };
        };
        pub fn deinit(this: *PersonInfo, ator: Allocator) void {
            this.fo_connections.deinit(ator);
            this.person.deinit(ator);
        }
    }; // FOConnections

    pub const Error = error {
        person_not_unregistered,   family_not_unregistered,
        person_already_registered, family_already_registered,
        person_negative_id,        family_negative_id,
        person_not_registered,     family_not_registered,
        person_key_overfull,       family_key_overfull,
        OutOfMemory,
        // I don't know if this is clever
        // this is for callbacks
        UserDefinedError1, UserDefinedError2, UserDefinedError3,
        UserDefinedError4, UserDefinedError5, UserDefinedError6,
        UserDefinedError7, UserDefinedError8, UserDefinedError9,
    };

    pub const Settings = struct {
        seed: ?u64 = null,
    };
    pub fn init(
        ator: Allocator,
        comptime settings: Settings,
    ) if (settings.seed) |_| FamilyTree else std.os.OpenError!FamilyTree {
        var prng = if (settings.seed) |seed| Prng.init(seed)
                     else
                         Prng.init(blk: {
                             var seed: u64 = undefined;
                             try std.os.getrandom(std.mem.asBytes(&seed));
                             break :blk seed;
                         })
        ;
        return FamilyTree{.ator=ator, .rand=prng};
    }
    pub fn deinit(this: *FamilyTree) void {
        var f_it = this.fk2family.valueIterator();
        while (f_it.next()) |f_ptr| {
            f_ptr.deinit(this.ator);
        }
        this.fk2family.deinit(this.ator);
        var pi_it = this.pk2person_info.valueIterator();
        while (pi_it.next()) |pi_ptr| {
            pi_ptr.deinit(this.ator);
        }
        this.pk2person_info.deinit(this.ator);
    }

    pub fn randPersonKey(this: *FamilyTree) PersonKey {
        return this.rand.random().int(PersonKey);
    }
    pub fn randFamilyKey(this: *FamilyTree) FamilyKey {
        return this.rand.random().int(FamilyKey);
    }

    pub fn personKeyIsFree(self: FamilyTree, pk: PersonKey) bool {
        return !self.pk2person_info.contains(pk);
    }
    pub fn familyKeyIsFree(self: FamilyTree, fk: FamilyKey) bool {
        return !self.fk2family.contains(fk);
    }
    pub fn personKeyIsRegistered(self: FamilyTree, pk: PersonKey) bool {
        return self.pk2person.contains(pk);
    }
    pub fn familyKeyIsRegistered(self: FamilyTree, fk: FamilyKey) bool {
        return self.fk2family.contains(fk);
    }

    pub fn genPersonKey(this: *FamilyTree) !PersonKey {
        var res: PersonKey = this.randPersonKey();
        var counter: @TypeOf(max_pkgen_iter) = 0;
        while (!this.personKeyIsFree(res) and counter < max_pkgen_iter) :
                ({res = this.randPersonKey(); counter += 1;})
        {}
        if (!this.personKeyIsFree(res)) {
            logger.err("in FamilyTree.genPersonKey() reached max_pkgen_iter", .{});
            return Error.person_key_overfull;
        }
        return res;
    }
    pub fn genFamilyKey(this: *FamilyTree) !FamilyKey {
        var res: FamilyKey = this.randFamilyKey();
        var counter: @TypeOf(max_fkgen_iter) = 0;
        while (!this.familyKeyIsFree(res) and counter < max_fkgen_iter) :
                ({res = this.randFamilyKey(); counter += 1;})
        {}
        if (!this.familyKeyIsFree(res)) {
            logger.err("in FamilyTree.genFamilyKey() reached max_fkgen_iter", .{});
            return Error.family_key_overfull;
        }
        return res;
    }

    pub fn registerPerson(this: *FamilyTree, person: *Person) !PersonKey {
        if (person.id < 0) { // need to generate new person key
            if (person.id != person_unregistered) {
                logger.err(
                    "in FamilyTree.registerPerson()" ++
                    " person w/ id={d} is not unregistered"
                    , .{person.id}
                );
                return Error.person_not_unregistered;
            }
            const key = try this.genPersonKey();
            person.id = key;
            try this.pk2person_info.putNoClobber(this.ator, key, .{.person=person.*});
            person.* = Person{.id=person_invalidated};
            return key;
        } else { // register using person id as person key
            if (this.pk2person_info.contains(@intCast(PersonKey, person.id))) {
                logger.err(
                    "in FamilyTree.registerPerson()" ++
                    " person w/ id={d} is already registered"
                    , .{person.id}
                );
                return Error.person_already_registered;
            }
            const key = @intCast(PersonKey, person.id);
            try this.pk2person_info.putNoClobber(this.ator, key, .{.person=person.*});
            person.* = Person{.id=person_invalidated};
            return key;
        }
    }
    pub fn registerFamily(this: *FamilyTree, family: *Family) !FamilyKey {
        if (family.id < 0) { // need to generate new family key
            if (family.id != family_unregistered) {
                logger.err(
                    "in FamilyTree.registerFamily()" ++
                    " family w/ id={d} is not unregistered"
                    , .{family.id}
                );
                return Error.family_not_unregistered;
            }
            const key = try this.genFamilyKey();
            family.id = key;
            try this.fk2family.putNoClobber(this.ator, key, family.*);
            family.* = Family{.id=family_invalidated};
            return key;
        } else { // register using family id as family key
            if (this.fk2family.contains(@intCast(FamilyKey, family.id))) {
                logger.err(
                    "in FamilyTree.registerFamily()" ++
                    " family w/ id={d} is already registered"
                    , .{family.id}
                );
                return Error.family_already_registered;
            }
            const key = @intCast(FamilyKey, family.id);
            try this.fk2family.putNoClobber(this.ator, key, family.*);
            family.* = Family{.id=family_invalidated};
            return key;
        }
    }

    pub fn createPerson(this: *FamilyTree) !PersonKey {
        const key = try this.genPersonKey();
        var p = Person{.id=key};
        return try this.registerPerson(&p);
    }
    pub fn createFamily(this: *FamilyTree) !FamilyKey {
        const key = try this.genFamilyKey();
        var f = Family{.id=key};
        return try this.registerFamily(&f);
    }
    pub fn createPersonPtr(this: *FamilyTree) !*Person {
        const key = try this.createPerson();
        return this.getPersonPtr(key).?;
    }
    pub fn createPersonInfoPtr(this: *FamilyTree) !*PersonInfo {
        const key = try this.createPerson();
        return this.getPersonInfoPtr(key).?;
    }
    pub fn createFamilyPtr(this: *FamilyTree) !*Family {
        const key = try this.createFamily();
        return this.getFamilyPtr(key).?;
    }

    pub fn getPersonPtr(this: *FamilyTree, key: PersonKey) ?*Person {
        const info_ptr = this.getPersonInfoPtr(key);
        return if (info_ptr) |ip| {
            &ip.person;
        } else {
            null;
        };
    }
    pub fn getPersonInfoPtr(this: *FamilyTree, key: PersonKey) ?*PersonInfo {
        return this.pk2person_info.getPtr(key);
    }
    pub fn getFamilyPtr(this: *FamilyTree, key: FamilyKey) ?*Family {
        return this.fk2family.getPtr(key);
    }
    pub fn visitFamilies(
        this: *FamilyTree,
        visitor: anytype,
        userdata: anytype,
    ) !void {
        var f_it = this.fk2family.valueIterator();
        while (f_it.next()) |f_ptr| {
            if (!try visitor(f_ptr, userdata))
                break;
        }
    }
    pub fn visitPeople(
        this: *FamilyTree,
        visitor: anytype,
        userdata: anytype,
    ) !void {
        var pi_it = this.pk2person_info.valueIterator();
        while (pi_it.next()) |pi_ptr| {
            if (!try visitor(pi_ptr, userdata))
                break;
        }
    }
    fn danglingPeopleFamilyShallowVisitor(
        family: *Family,
        userdata: struct {
            tree: *FamilyTree,
            found_dangling: *bool,
        },
    ) !bool {
        const tree = userdata.tree;
        const found_dangling = userdata.found_dangling;
        inline for (.{Family.ParentEnum.father, Family.ParentEnum.mother}) |pe| {
            if (switch (pe) {
                .father => family.father_id,
                .mother => family.mother_id,
            }) |parent_id| {
                if (parent_id < 0) {
                    logger.err(
                        "in FamilyTree.danglingPeopleFamilyShallowVisitor()" ++
                        " encountered negative {s} id={d}"
                        , .{pe.asText(), parent_id}
                    );
                    return Error.person_negative_id;
                }
                if (tree.personKeyIsFree(@intCast(PersonKey, parent_id))) {
                    found_dangling.* = true;
                    return false; // breaks loop in visitFamilies()
                }
            }
        }
        for (family.children_ids.data.items) |child_id| {
            if (child_id < 0) {
                logger.err(
                    "in FamilyTree.danglingPeopleFamilyShallowVisitor()" ++
                    " encountered negative child id={d}"
                    , .{child_id}
                );
                return Error.person_negative_id;
            }
            if (tree.personKeyIsFree(@intCast(PersonKey, child_id))) {
                found_dangling.* = true;
                return false; // breaks loop in visitFamilies()
            }
        }
        found_dangling.* = false;
        return true; // continues loop in visitFamilies()
    }
    pub fn hasNoDanglingPersonKeysFamiliesShallow(this: *FamilyTree) !bool {
        // this is probably not very efficient due to duplicate checks
        var found_dangling = false;
        const visitor_data = .{.tree=this, .found_dangling=&found_dangling};
        try this.visitFamilies(danglingPeopleFamilyShallowVisitor, visitor_data);
        return !found_dangling;
    }
    fn danglingPeoplePersonShallowVisitor(
        person_info: *PersonInfo,
        userdata: struct {
            tree: *FamilyTree,
            found_dangling: *bool,
        },
    ) !bool { // never actually errors
        const tree = userdata.tree;
        const found_dangling = userdata.found_dangling;
        const fo_connections = person_info.fo_connections;
        inline for (.{
            PersonInfo.FOConnections.ParentEnum.father,
            PersonInfo.FOConnections.ParentEnum.mother,
            PersonInfo.FOConnections.ParentEnum.mit_mother,
        }) |pe| {
            if (switch (pe) {
                .father => fo_connections.father_key,
                .mother => fo_connections.mother_key,
                .mit_mother => fo_connections.mit_mother_key,
            }) |pk| {
                if (tree.personKeyIsFree(pk)) {
                    found_dangling.* = true;
                    return false; // breaks loop in visitPeople()
                }
            }
        }
        for (fo_connections.children.items) |child_key| {
            if (tree.personKeyIsFree(child_key)) {
                found_dangling.* = true;
                return false; // breaks loop in visitPeople()
            }
        }
        return true; // continues loop in visitPeople()
    }
    pub fn hasNoDanglingPersonKeysPeopleShallow(this: *FamilyTree) !bool {
        // this is probably not very efficient due to duplicate checks
        var found_dangling = false;
        const visitor_data = .{.tree=this, .found_dangling=&found_dangling};
        try this.visitPeople(danglingPeoplePersonShallowVisitor, visitor_data);
        return !found_dangling;
    }
    fn danglingFamiliesPersonShallowVisitor(
        person_info: *PersonInfo,
        userdata: struct {
            tree: *FamilyTree,
            found_dangling: *bool,
        },
    ) !bool {
        const tree = userdata.tree;
        const found_dangling = userdata.found_dangling;
        const fo_connections = person_info.fo_connections;
        for (fo_connections.families.items) |family_key| {
            if (tree.familyKeyIsFree(family_key)) {
                found_dangling.* = true;
                return false; // breaks loop in visitPeople()
            }
        }
        return true; // continues loop in visitPeople()
    }
    pub fn hasNoDanglingFamilyKeysPeopleShallow(this: *FamilyTree) !bool {
        var found_dangling = false;
        const visitor_data = .{.tree=this, .found_dangling=&found_dangling};
        try this.visitPeople(danglingFamiliesPersonShallowVisitor, visitor_data);
        return !found_dangling;
    }
    fn assignPersonInfoFamiliesFamilyShallowVisitor(
        family: *Family,
        userdata: struct {
            tree: *FamilyTree,
        },
    ) !bool { // does no checks
        const tree = userdata.tree;
        inline for (.{.father, .mother}) |pe| {
            if (switch (pe) {
                .father => family.father_id,
                .mother => family.mother_id,
                else => @compileError(
                    "nonexhaustive switch on ParentEnum in" ++
                    " assignPersonInfoFamiliesFamilyShallowVisitor()"
                ),
            }) |pid| {
                const person_info_ptr = tree.getPersonInfoPtr(@intCast(PersonKey, pid)).?;
                const fo_connections_ptr = &person_info_ptr.fo_connections;
                _ = try fo_connections_ptr.addFamily(
                    @intCast(FamilyKey, family.id),
                    tree.ator,
                );
            }
        }
        for (family.children_ids.data.items) |child_id| {
            const person_info_ptr = tree.getPersonInfoPtr(@intCast(PersonKey, child_id)).?;
            const fo_connections_ptr = &person_info_ptr.fo_connections;
            _ = try fo_connections_ptr.addFamily(
                @intCast(FamilyKey, family.id),
                tree.ator,
            );
        }
        return true; // continues loop in visitFamilies()
    }
    pub fn assignPeopleTheirFamilies(this: *FamilyTree) !void {
        try this.visitFamilies(assignPersonInfoFamiliesFamilyShallowVisitor, .{.tree=this});
    }
    fn assignPeopleInfoChildrenPersonShallowVisitor(
        person_info: *PersonInfo,
        userdata: struct {
            tree: *FamilyTree,
        },
    ) !bool {
        const tree = userdata.tree;
        const fo_connections = person_info.fo_connections;
        if (fo_connections.father_key) |fak| {
            const father_info_ptr = tree.getPersonInfoPtr(fak).?;
            const fo_connections_ptr = &father_info_ptr.fo_connections;
            _ = try fo_connections_ptr.addChild(
                @intCast(PersonKey, person_info.person.id),
                tree.ator,
            );
        }
        if (fo_connections.mother_key) |fak| {
            const mother_info_ptr = tree.getPersonInfoPtr(fak).?;
            const fo_connections_ptr = &mother_info_ptr.fo_connections;
            _ = try fo_connections_ptr.addChild(
                @intCast(PersonKey, person_info.person.id),
                tree.ator,
            );
        }
        return true; // continues loop in visitPeople()
    }
    pub fn assignPeopleTheirChildren(this: *FamilyTree) !void {
        try this.visitPeople(assignPeopleInfoChildrenPersonShallowVisitor, .{.tree=this});
    }
    pub fn buildConnections(this: *FamilyTree) !void {
        if (!try this.hasNoDanglingPersonKeysFamiliesShallow()) {
            logger.err(
                "in FamilyTree.buildConnections() family stores dangling person key"
                , .{}
            );
            return Error.person_not_registered;
        }
        if (!try this.hasNoDanglingPersonKeysPeopleShallow()) {
            logger.err(
                "in FamilyTree.buildConnections() person stores dangling person key"
                , .{}
            );
            return Error.person_not_registered;
        }
        if (!try this.hasNoDanglingFamilyKeysPeopleShallow()) {
            logger.err(
                "in FamilyTree.buildConnections() person stores dangling family key"
                , .{}
            );
            return Error.family_not_registered;
        }
        try this.assignPeopleTheirFamilies();
        try this.assignPeopleTheirChildren();
    }

    pub const FromJsonError = error { bad_type, bad_field, };
    pub fn readFromJson(
        this: *FamilyTree,
        json_tree: *json.Value,
        comptime options: JsonReadOptions,
    ) !void {
        options.AOCheck();
        logger.debug("FamilyTree.readFromJson() w/ options={s}", .{options.str_mgmt.asText()});
        switch (json_tree.*) {
            json.Value.Object => |jtmap| {
                inline for (.{.people, .families}) |pfe| {
                    const pfs = switch (pfe) {
                        .people => "people",
                        .families => "families",
                        else => @compileError("nonexhaustive switch on people-families enum"),
                    };
                    if (jtmap.get(pfs)) |*payload| {
                        try this.readPayloadFromJson(payload, pfe, options);
                    }
                }
            },
            else => {
                logger.err(
                    "in FamilyTree.readFromJson() j_tree is not of type {s}"
                    , .{"json.ObjectMap"},
                );
                return FromJsonError.bad_type;
            },
        }
        try this.buildConnections();
    }
    pub fn readPayloadFromJson(
        this: *FamilyTree,
        json_payload: *json.Value,
        comptime which: @TypeOf(.enum_literal),//enum {people, families},
        comptime options: JsonReadOptions,
    ) !void {
        options.AOCheck();
        switch (json_payload.*) {
            json.Value.Array => |parr| {
                switch (which) {
                    .people => {
                        for (parr.items) |*jperson| {
                            var person = Person{.id=person_invalidated};
                            if (options.use_ator) {
                                try person.readFromJson(
                                    jperson,
                                    this.ator,
                                    options.str_mgmt.asEnumLiteral(),
                                );
                            } else {
                                try person.readFromJson(
                                    jperson,
                                    null,
                                    options.str_mgmt.asEnumLiteral(),
                                );
                            }
                            errdefer {
                                if (options.use_ator)
                                    switch (options.str_mgmt) {
                                        .weak => {},
                                        else => {
                                            person.deinit(this.ator);
                                        },
                                    };
                            }
                            const pk = try this.registerPerson(&person);
                            logger.debug("FamilyTree: registering person with id {}", .{person.id});
                            var pinfo_ptr = this.getPersonInfoPtr(pk).?;
                            switch (jperson.*) {
                                json.Value.Object => |jpmap| {
                                    inline for (.{.father, .mother, .mit_mother}) |fme| {
                                        const fmks = switch (fme) {
                                            .father => "father_key",
                                            .mother => "mother_key",
                                            .mit_mother => "mit_mother_key",
                                            else => @compileError("nonexhaustive switch on father-(mit)mother enum"),
                                        };
                                        if (jpmap.get(fmks)) |jfm| {
                                            switch (jfm) {
                                                json.Value.Integer => |jfmi| {
                                                    if (jfmi > max_pid or jfmi < min_pid) {
                                                        logger.err(
                                                            "in FamilyTree.readPayloadFromJson()" ++
                                                            " j_parent_key is out of bounds"
                                                            , .{},
                                                        );
                                                        return FromJsonError.bad_field;
                                                    }
                                                    @field(pinfo_ptr.fo_connections, fmks) = @intCast(PersonKey, jfmi);
                                                },
                                                json.Value.Null => {
                                                    @field(pinfo_ptr.fo_connections, fmks) = null;
                                                },
                                                else => {
                                                    logger.err(
                                                        "in FamilyTree.readPayloadFromJson()" ++
                                                        " j_parent_key is not of type {s}"
                                                        , .{"json.Int"}
                                                    );
                                                    return FromJsonError.bad_type;
                                                },
                                            }
                                        }
                                    }
                                },
                                else => {},
                            }
                        }
                    },
                    .families => {
                        for (parr.items) |jfamily| {
                            var family = Family{.id=family_invalidated};
                            try family.readFromJson(
                                jfamily,
                                if (options.use_ator) this.ator else null,
                            );
                            errdefer {
                                if (options.use_ator)
                                    switch (options.str_mgmt) {
                                        .weak => {},
                                        else => {
                                            family.deinit(this.ator);
                                        },
                                    };
                            }
                            _ = try this.registerFamily(&family);
                        }
                    },
                    else => {
                        @compileError("bruh");
                    },
                }
            },
            else => {
                logger.err(
                    "in FamilyTree.readPeopleFromJson() j_people is not of type {s}"
                    , .{"json.ObjectMap"},
                );
                return FromJsonError.bad_type;
            }
        }
    }
    pub fn readFromJsonSourceStr(
        this: *FamilyTree,
        source_str: []const u8,
        comptime options: JsonReadOptions,
    ) !void {
        // TODO should only .copy be allowed???
        var parser = json.Parser.init(this.ator, false); // strings are copied in readFromJson
        defer parser.deinit();
        var tree = try parser.parse(source_str);
        defer tree.deinit();
        try this.readFromJson(&tree.root, options);
    }

    pub const JsonReadOptions = struct {
        str_mgmt: StrMgmt = .copy,
        use_ator: bool = true,
        fn AOCheck(comptime self: JsonReadOptions) void {
            switch (self.str_mgmt) {
                .copy => {
                    if (!self.use_ator)
                        @compileError("FamilyTree: can't copy w\\o allocator");
                },
                .move, .weak => {},
            }
        }
    };

    pub fn toJson(
        self: FamilyTree,
        _ator: Allocator,
        comptime settings: util.ToJsonSettings,
    ) util.ToJsonError!util.ToJsonResult {
        // TODO make 2 if's 1
        var res = util.ToJsonResult{
            .value = undefined,
            .arena = if (settings.apply_arena) ArenaAllocator.init(_ator) else null,
        };
        errdefer res.deinit();
        const ator = if (res.arena) |*arena| arena.allocator() else _ator;
        res.value = .{.Object = json.ObjectMap.init(ator)};
        const settings_to_pass = util.ToJsonSettings{
            .allow_overload=true,
            .apply_arena=false,
        };

        var people_array = json.Value{.Array = json.Array.init(ator)};
        try people_array.Array.ensureUnusedCapacity(self.pk2person_info.count());
        var piter = self.pk2person_info.valueIterator();
        while (piter.next()) |person_info| {
            var person_json = (try person_info.person.toJson(ator, settings_to_pass)).value;
            inline for (.{"father_key", "mother_key", "mit_mother_key"}) |ancestor_key| {
                try person_json.Object.ensureUnusedCapacity(3); // DANGER
                person_json.Object.putAssumeCapacity(
                    ancestor_key,
                    (try util.toJson(
                        @field(person_info.fo_connections, ancestor_key),
                        ator,
                        settings_to_pass,
                    )).value,
                );
            }
            people_array.Array.appendAssumeCapacity(person_json);
        }

        var families_array = json.Value{.Array = json.Array.init(ator)};
        try families_array.Array.ensureUnusedCapacity(self.fk2family.count());
        var fiter = self.fk2family.valueIterator();
        while (fiter.next()) |family| {
            families_array.Array.appendAssumeCapacity(
                (try family.toJson(ator, settings_to_pass)).value
            );
        }

        try res.value.Object.put("people", people_array);
        try res.value.Object.put("families", families_array);
        return res;
    }

    pub fn personCount(self: FamilyTree) usize {
        return self.pk2person_info.count();
    }
    pub fn familyCount(self: FamilyTree) usize {
        return self.fk2family.count();
    }

    pub fn equal(
        self: FamilyTree,
        other: FamilyTree,
        comptime settings: util.EqualSettings
    ) bool {
        _ = settings;
        var lpiter = self.pk2person_info.iterator();
        if (self.personCount() != other.personCount()) {
            return false;
        }
        while (lpiter.next()) |lentry| {
            if (other.pk2person_info.get(lentry.key_ptr.*)) |rinfo| {
                if (!util.equal(lentry.value_ptr.*, rinfo, .{})) {
                    return false;
                }
            } else {
                return false;
            }
        }

        var lfiter = self.fk2family.iterator();
        if (self.familyCount() != other.familyCount()) {
            return false;
        }
        while (lfiter.next()) |lentry| {
            if (other.fk2family.get(lentry.key_ptr.*)) |rval| {
                if (!util.equal(lentry.value_ptr.*, rval, .{})) {
                    return false;
                }
            } else {
                return false;
            }
        }

        return true;
    }

}; // FamilyTree



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



const testing = std.testing;
const tator = testing.allocator;
const expect = testing.expect;
const expectError = testing.expectError;
const expectEqual = testing.expectEqual;

test "register" {
    var ft = FamilyTree.init(tator, .{.seed=0});
    defer ft.deinit();
    var up = Person{.id=-1};
    const pk = try ft.registerPerson(&up);
    try expectEqual(up.id, -2);
    var uf = Family{.id=-1};
    const fk = try ft.registerFamily(&uf);
    try expectEqual(uf.id, -2);
    try expectError(anyerror.person_not_unregistered, ft.registerPerson(&up));
    try expectError(anyerror.family_not_unregistered, ft.registerFamily(&uf));
    const rpk = try ft.genPersonKey();
    var rp = Person{.id=rpk};
    try expectEqual(rpk, try ft.registerPerson(&rp));
    try expectEqual(rp.id, -2);
    const rfk = try ft.genFamilyKey();
    var rf = Family{.id=rfk};
    try expectEqual(rfk, try ft.registerFamily(&rf));
    try expectEqual(rf.id, -2);
    up = Person{.id=pk};
    uf = Family{.id=fk};
    rp = Person{.id=rpk};
    rf = Family{.id=rfk};
    try expectError(anyerror.person_already_registered, ft.registerPerson(&up));
    try expectError(anyerror.person_already_registered, ft.registerPerson(&rp));
    try expectError(anyerror.family_already_registered, ft.registerFamily(&uf));
    try expectError(anyerror.family_already_registered, ft.registerFamily(&rf));
}

test "dangling people" {
    var ft = FamilyTree.init(tator, .{.seed=0});
    defer ft.deinit();
    var c: u32 = 0;
    while (c < 32) : (c+=1) { // create 32 people w/ ids < 64
        var key = try ft.genPersonKey();
        while (!ft.personKeyIsFree(key % 64)) {
            key = try ft.genPersonKey();
        }
        var p = Person{.id=key%64};
        _ = try ft.registerPerson(&p);
    }
    while (c < 16) : (c+=1) { // create 16 random families
        var fkey = ft.rand.random().int(u6);
        var mkey = ft.rand.random().int(u6);
        var c1key = ft.rand.random().int(u6);
        var c2key = ft.rand.random().int(u6);
        var c3key = ft.rand.random().int(u6);
        inline for (.{.f, .m, .c1, .c2, .c3}) |pe| {
            var k_ptr = switch (pe) {
                .f => &fkey, .m => &mkey, .c1 => &c1key, .c2 => &c2key, .c3 => &c3key, else => @compileError("bruh"),
            };
            while (ft.personKeyIsFree(k_ptr.*)) {
                k_ptr.* = ft.rand.random().int(u6);
            }
        }
        var f = Family{.id=-1, .father_id=fkey, .mother_id=mkey};
        errdefer f.deinit(tator);
        // try f.children_ids.data.ensureUnusedCapacity(tator, 3);
        try f.addChild(c1key, tator);
        try f.addChild(c2key, tator);
        try f.addChild(c3key, tator);
        _ = try ft.registerFamily(&f);
    }
    try expect(try ft.hasNoDanglingPersonKeysFamiliesShallow());
    try expect(try ft.hasNoDanglingPersonKeysPeopleShallow());
    try expect(try ft.hasNoDanglingFamilyKeysPeopleShallow());
    var f = Family{.id=-1, .father_id=try ft.genPersonKey()};
    _ = try ft.registerFamily(&f);
    try expect(!try ft.hasNoDanglingPersonKeysFamiliesShallow());
    var pk = ft.rand.random().int(u6);
    while (ft.personKeyIsFree(pk)) {
        pk = ft.rand.random().int(u6);
    }
    const person_info_ptr = ft.getPersonInfoPtr(pk).?;
    person_info_ptr.fo_connections.father_key = try ft.genPersonKey();
    try expect(!try ft.hasNoDanglingPersonKeysPeopleShallow());
    try person_info_ptr.fo_connections.families.append(tator, try ft.genFamilyKey());
    try expect(!try ft.hasNoDanglingFamilyKeysPeopleShallow());
}

test "assign people, families" {
    var tree = FamilyTree.init(tator, .{.seed=0});
    defer tree.deinit();
    const fk: FamilyTree.PersonKey = 1;
    const mk: FamilyTree.PersonKey = 2;
    const c1k: FamilyTree.PersonKey = 3;
    const c2k: FamilyTree.PersonKey = 4;
    const c3k: FamilyTree.PersonKey = 5;
    var f = Person{.id=fk};
    var m = Person{.id=mk};
    try expectEqual(fk, try tree.registerPerson(&f));
    try expectEqual(mk, try tree.registerPerson(&m));
    var c1 = Person{.id=c1k};
    var c2 = Person{.id=c2k};
    var c3 = Person{.id=c3k};
    try expectEqual(c1k, try tree.registerPerson(&c1));
    try expectEqual(c2k, try tree.registerPerson(&c2));
    try expectEqual(c3k, try tree.registerPerson(&c3));
    const fip = tree.getPersonInfoPtr(fk).?;
    const mip = tree.getPersonInfoPtr(mk).?;
    const c1ip = tree.getPersonInfoPtr(c1k).?;
    c1ip.fo_connections.father_key = fk;
    c1ip.fo_connections.mother_key = mk;
    const c2ip = tree.getPersonInfoPtr(c2k).?;
    c2ip.fo_connections.father_key = fk;
    c2ip.fo_connections.mother_key = mk;
    const c3ip = tree.getPersonInfoPtr(c3k).?;
    c3ip.fo_connections.father_key = fk;
    c3ip.fo_connections.mother_key = mk;
    try expect(!fip.fo_connections.hasChild(c1k));
    try expect(!fip.fo_connections.hasChild(c2k));
    try expect(!fip.fo_connections.hasChild(c3k));
    try expect(!mip.fo_connections.hasChild(c1k));
    try expect(!mip.fo_connections.hasChild(c2k));
    try expect(!mip.fo_connections.hasChild(c3k));
    try tree.assignPeopleTheirChildren();
    try expect(fip.fo_connections.hasChild(c1k));
    try expect(fip.fo_connections.hasChild(c2k));
    try expect(fip.fo_connections.hasChild(c3k));
    try expect(mip.fo_connections.hasChild(c1k));
    try expect(mip.fo_connections.hasChild(c2k));
    try expect(mip.fo_connections.hasChild(c3k));
    const famk: FamilyTree.FamilyKey = 1;
    var fam = Family{.id=famk, .father_id=fk, .mother_id=mk};
    try fam.addChild(c1k, tator);
    try fam.addChild(c2k, tator);
    try fam.addChild(c3k, tator);
    try expectEqual(famk, try tree.registerFamily(&fam));
    const folks = [_]FamilyTree.PersonKey{fk, mk, c1k, c2k, c3k};
    for (folks) |k| {
        try expect(!tree.getPersonInfoPtr(k).?.fo_connections.hasFamily(famk));
    }
    try tree.assignPeopleTheirFamilies();
    for (folks) |k| {
        try expect(tree.getPersonInfoPtr(k).?.fo_connections.hasFamily(famk));
    }
}

test "build connections" {
    var tree = FamilyTree.init(tator, .{.seed=0});
    defer tree.deinit();
    const fk: FamilyTree.PersonKey = 1;
    const mk: FamilyTree.PersonKey = 2;
    const c1k: FamilyTree.PersonKey = 3;
    const c2k: FamilyTree.PersonKey = 4;
    const c3k: FamilyTree.PersonKey = 5;
    var f = Person{.id=fk};
    var m = Person{.id=mk};
    try expectEqual(fk, try tree.registerPerson(&f));
    try expectEqual(mk, try tree.registerPerson(&m));
    var c1 = Person{.id=c1k};
    var c2 = Person{.id=c2k};
    var c3 = Person{.id=c3k};
    try expectEqual(c1k, try tree.registerPerson(&c1));
    try expectEqual(c2k, try tree.registerPerson(&c2));
    try expectEqual(c3k, try tree.registerPerson(&c3));
    const fip = tree.getPersonInfoPtr(fk).?;
    const mip = tree.getPersonInfoPtr(mk).?;
    const c1ip = tree.getPersonInfoPtr(c1k).?;
    c1ip.fo_connections.father_key = fk;
    c1ip.fo_connections.mother_key = mk;
    const c2ip = tree.getPersonInfoPtr(c2k).?;
    c2ip.fo_connections.father_key = fk;
    c2ip.fo_connections.mother_key = mk;
    const c3ip = tree.getPersonInfoPtr(c3k).?;
    c3ip.fo_connections.father_key = fk;
    c3ip.fo_connections.mother_key = mk;
    const famk: FamilyTree.FamilyKey = 1;
    var fam = Family{.id=famk, .father_id=fk, .mother_id=mk};
    try fam.addChild(c1k, tator);
    try fam.addChild(c2k, tator);
    try fam.addChild(c3k, tator);
    try expectEqual(famk, try tree.registerFamily(&fam));
    const folks = [_]FamilyTree.PersonKey{fk, mk, c1k, c2k, c3k};

    try expect(!fip.fo_connections.hasChild(c1k));
    try expect(!fip.fo_connections.hasChild(c2k));
    try expect(!fip.fo_connections.hasChild(c3k));
    try expect(!mip.fo_connections.hasChild(c1k));
    try expect(!mip.fo_connections.hasChild(c2k));
    try expect(!mip.fo_connections.hasChild(c3k));
    for (folks) |k| {
        try expect(!tree.getPersonInfoPtr(k).?.fo_connections.hasFamily(famk));
    }
    try tree.buildConnections();
    try expect(fip.fo_connections.hasChild(c1k));
    try expect(fip.fo_connections.hasChild(c2k));
    try expect(fip.fo_connections.hasChild(c3k));
    try expect(mip.fo_connections.hasChild(c1k));
    try expect(mip.fo_connections.hasChild(c2k));
    try expect(mip.fo_connections.hasChild(c3k));
    for (folks) |k| {
        try expect(tree.getPersonInfoPtr(k).?.fo_connections.hasFamily(famk));
    }

    const fam_ptr = tree.getFamilyPtr(famk).?;
    try fam_ptr.addChild(6, tator);
    try expectError(anyerror.person_not_registered, tree.buildConnections());
    _ = fam_ptr.children_ids.data.pop();
    try tree.buildConnections();
    fip.fo_connections.father_key = 6;
    try expectError(anyerror.person_not_registered, tree.buildConnections());
    fip.fo_connections.father_key = null;
    try tree.buildConnections();
    try expect(try fip.fo_connections.addFamily(2, tator));
    try expectError(anyerror.family_not_registered, tree.buildConnections());
    _ = fip.fo_connections.families.pop();
    try tree.buildConnections();
}

const healthy_family_src =
    \\{
    \\  "people": [
    \\    {"id": 1, "name": "father"},
    \\    {"id": 2, "name": "son", "father_key": 1},
    \\    {"id": 3, "name": "adopted"},
    \\    {"id": 4, "name": "bastard", "father_key": 1}
    \\  ],
    \\  "families": [
    \\    {"id": 1, "father_id": 1, "children_ids": [2, 3]}
    \\  ]
    \\}
;

test "read from json" {
    var ft = FamilyTree.init(tator, .{.seed=0});
    defer ft.deinit();
    try ft.readFromJsonSourceStr(healthy_family_src, .{});
    const father_info = ft.getPersonInfoPtr(1).?;
    const son_info = ft.getPersonInfoPtr(2).?;
    const adopted_info = ft.getPersonInfoPtr(3).?;
    const bastard_info = ft.getPersonInfoPtr(4).?;

    try expectEqual(father_info.person.id, 1);
    try expectEqual(son_info.person.id, 2);
    try expectEqual(adopted_info.person.id, 3);
    try expectEqual(bastard_info.person.id, 4);

    try expectEqual(son_info.fo_connections.father_key, 1);
    try expectEqual(adopted_info.fo_connections.father_key, null);
    try expectEqual(bastard_info.fo_connections.father_key, 1);

    try expect(father_info.fo_connections.hasChild(2));
    try expect(!father_info.fo_connections.hasChild(3));
    try expect(father_info.fo_connections.hasChild(4));

    const family = ft.getFamilyPtr(1).?;
    try expectEqual(family.father_id, 1);
    try expect(family.hasChild(2));
    try expect(family.hasChild(3));
    try expect(!family.hasChild(4));
}

test "to json" {
    var ft = FamilyTree.init(tator, .{.seed=0});
    defer ft.deinit();
    try ft.readFromJsonSourceStr(healthy_family_src, .{});
    var jft = try ft.toJson(tator, .{});
    defer jft.deinit();
    var tf = FamilyTree.init(tator, .{.seed=0});
    defer tf.deinit();
    try tf.readFromJson(&jft.value, .{});
    try expect(util.equal(ft, tf, .{}));
}



