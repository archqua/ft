const std = @import("std");
const person_module = @import("person.zig");
const family_module = @import("family.zig");
const json = std.json;


const Person = person_module.Person;
const Family = family_module.Family;
const Allocator = std.mem.Allocator;
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
    pub const max_pid = switch (@typeInfo(Person.Id).Int.Signedness) {
        .signed => ~@bitReverse(Person.Id, 1),
        .unsigned => @compileError("wrong understanding of Person.Id as signed int"),
    };
    pub const min_pid = @as(Person.Id, 0);
    pub const max_fid = switch (@typeInfo(Family.Id).Int.Signedness) {
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
            // by blood
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
    };

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
        for (family.children_ids.items) |child_id| {
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
        for (family.children_ids.items) |child_id| {
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
        try f.children_ids.ensureUnusedCapacity(tator, 3);
        f.children_ids.appendAssumeCapacity(c1key);
        f.children_ids.appendAssumeCapacity(c2key);
        f.children_ids.appendAssumeCapacity(c3key);
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
    try fam.children_ids.append(tator, c1k);
    try fam.children_ids.append(tator, c2k);
    try fam.children_ids.append(tator, c3k);
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
    try fam.children_ids.append(tator, c1k);
    try fam.children_ids.append(tator, c2k);
    try fam.children_ids.append(tator, c3k);
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
    try fam_ptr.children_ids.append(tator, 6);
    try expectError(anyerror.person_not_registered, tree.buildConnections());
    _ = fam_ptr.children_ids.pop();
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
