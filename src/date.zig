const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;
const logger = std.log.scoped(.ft);
const util = @import("util.zig");

pub const Date = struct {
    /// comptime interfaces: [ readFromJson, toJson ]
    day: ?u8 = null,
    month: ?u8 = null,
    year: ?i32 = null,

    pub const ValidationError = error { invalid_day, invalid_month, invalid_year, };
    pub const FromJsonError = error { bad_type, bad_field, bad_field_val, };
    const month2daycount = [12]u8{31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    pub fn validate(self: Date) ValidationError!void {
        if (self.year) |year| {
            if (year == 0) {
                logger.err("in Date.validate() invalid year {d}", .{year});
                return ValidationError.invalid_year;
            }
        }
        if (self.month) |month| {
            if (month == 0 or month > 12) {
                logger.err("in Date.validate() invalid month {d}", .{month});
                return ValidationError.invalid_month;
            }
            if (self.day) |day| {
                if (month != 2) {
                    if (day == 0 or day > Date.month2daycount[month-1]) {
                        logger.err(
                            "in Date.validate() invalid day {d} in month {d}"
                            , .{day, month}
                        );
                        return ValidationError.invalid_day;
                    }
                } else { // year-independent Febuary check
                    if (day == 0 or day > 29) {
                        logger.err(
                            "in Date.validate() invalid day {d} in month 2 (year unknown)"
                            , .{month}
                        );
                        return ValidationError.invalid_day;
                    }
                    if (day == 29) {
                        if (null == self.year) {
                            logger.warn(
                                "in Date.validate() suspicious day 29 in month 2 (year unknown)"
                                , .{}
                            );
                        }
                    }
                }
                if (self.year) |year| {
                    if (month == 2 and (
                            @rem(year, 400) == 0 or (
                                @rem(year, 100) != 0 and @rem(year, 4) == 0
                            )
                        )) {
                        // leap year
                        if (day == 0 or day > 29) {
                            logger.err(
                                "in Date.validate() invalid day {d} in month 2 (leap)"
                                , .{day}
                            );
                            return ValidationError.invalid_day;
                        }
                    } else {
                        if (day == 0 or day > Date.month2daycount[month-1]) {
                            logger.err(
                                "in Date.validate() invalid day {d}" ++
                                " in month {d} in year {d}"
                                , .{day, month, year}
                            );
                            return ValidationError.invalid_day;
                        }
                    }
                }
            } // day check finished
        } else { // month unknown
            if (self.day) |day| {
                if (day == 0 or day > 31) {
                    logger.err(
                        "in Date.validate() invalid day {d} (month unknown)"
                        , .{day}
                    );
                    return ValidationError.invalid_day;
                } else if (day > 28) {
                    logger.warn(
                        "in Date.validate() suspicious day {d} (month unknown)"
                        , .{day}
                    );
                }
            }
        }
    }
    pub fn dmy(d: u8, m: u8, y: i32) ValidationError!Date {
        const res = Date{.day=d, .month=m, .year=y};
        try res.validate();
        return res;
    }
    pub fn readFromJson(
        this: *Date,
        json_date: json.Value,
    ) (ValidationError||FromJsonError)!void {
        switch (json_date) {
            json.Value.Object => |map| {
                if (map.get("day")) |d| {
                    switch (d) {
                        json.Value.Integer => |int| {
                            if (int > 0 and int <= ~@as(u8, 0)) {
                                this.day = @intCast(@typeInfo(@TypeOf(this.day)).Optional.child, int);
                            } else {
                                logger.err(
                                    "in Date.readFromJson() bad day {d}"
                                    , .{int}
                                );
                                return FromJsonError.bad_field_val;
                            }
                        },
                        json.Value.Null => {
                            this.day = null;
                        },
                        else => {
                            logger.err(
                                "in Date.readFromJson() j_date.get(\"day\") " ++
                                " is not of type i64"
                                , .{}
                            );
                            return FromJsonError.bad_field;
                        },
                    }
                }
                if (map.get("month")) |m| {
                    switch (m) {
                        json.Value.Integer => |int| {
                            if (int > 0 and int <= ~@as(u8, 0)) {
                                this.month = @intCast(@typeInfo(@TypeOf(this.month)).Optional.child, int);
                            } else {
                                logger.err(
                                    "in Date.readFromJson() bad month {d}"
                                    , .{int}
                                );
                                return FromJsonError.bad_field_val;
                            }
                        },
                        json.Value.Null => {
                            this.month = null;
                        },
                        else => {
                            logger.err(
                                "in Date.readFromJson() j_date.get(\"month\") " ++
                                " is not of type i64"
                                , .{}
                            );
                            return FromJsonError.bad_field;
                        },
                    }
                }
                if (map.get("year")) |y| {
                    switch (y) {
                        json.Value.Integer => |int| {
                            if (
                                int >=  @bitReverse(i32, 1) and
                                int <= ~@bitReverse(i32, 1)
                            ) {
                                this.year = @intCast(@typeInfo(@TypeOf(this.year)).Optional.child, int);
                            }
                        },
                        json.Value.Null => {
                            this.year = null;
                        },
                        else => {
                            logger.err(
                                "in Date.readFromJson() j_date.get(\"year\")" ++
                                " is not of type i64"
                                , .{}
                            );
                            return FromJsonError.bad_field;
                        },
                    }
                }
                try this.validate();
            },
            else => {
                logger.err(
                    "in Date.readFromJson() j_date is not of type json.ObjectMap"
                    , .{}
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

const christ_birthday_source = 
\\{"day": 1, "month": 1, "year": 1}
;
const broken_source_type =
\\"asdf"
;
const broken_source_field =
\\{"day": "asdf"}
;
const broken_source_field_val =
\\{"day": -1}
;

test "basic" {
    var parser = json.Parser.init(testing.allocator, false);
    defer parser.deinit();
    var tree = try parser.parse(christ_birthday_source);
    defer tree.deinit();
    var date = Date{};
    try date.readFromJson(tree.root);
}
test "errors" {
    var date = Date{};
    date.day = 0;
    try expectError(Date.ValidationError.invalid_day, date.validate());
    date.day = 1;
    date.month = 13;
    try expectError(Date.ValidationError.invalid_month, date.validate());
    date.month = 1;
    date.year = 0;
    try expectError(Date.ValidationError.invalid_year, date.validate());
    date.year = 2004;
    date.month = 2;
    date.day = 29;
    try date.validate();
    date.year = 2003;
    try expectError(Date.ValidationError.invalid_day, date.validate());
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var tree = try parser.parse(broken_source_type);
        defer tree.deinit();
        try expectError(Date.FromJsonError.bad_type, date.readFromJson(tree.root));
    }
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var tree = try parser.parse(broken_source_field);
        defer tree.deinit();
        try expectError(Date.FromJsonError.bad_field, date.readFromJson(tree.root));
    }
    {
        var parser = json.Parser.init(testing.allocator, false);
        defer parser.deinit();
        var tree = try parser.parse(broken_source_field_val);
        defer tree.deinit();
        try expectError(Date.FromJsonError.bad_field_val, date.readFromJson(tree.root));
    }
}

test "to json" {
    var date = Date{.day = 1};
    var j_date = try util.toJson(date, testing.allocator, .{});
    defer j_date.deinit();
    var j_map = j_date.value.Object;
    try expectEqual(j_map.get("day").?.Integer, 1);
    try expectEqual(j_map.get("month").?.Null, {});
    try expectEqual(j_map.get("year").?.Null, {});
}
