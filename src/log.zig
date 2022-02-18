const std = @import("std");
const builtin = std.builtin;

// set log level to debug in Debug mode, info otherwise
pub const log_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    .ReleaseSafe, .ReleaseSmall, .ReleaseFast => .info,
};

// Define root.log to override the std implementation
pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    // Ignore all non-error logging from sources other than
    // .ft and .default
    const scope_prefix = "(" ++
        switch (scope) {
            .ft, .default => @tagName(scope),
            else => 
                if (@enumToInt(level) <= @enumToInt(std.log.Level.err))
                    @tagName(scope)
                else
                    return,
        } ++
    "): ";

    const prefix = "[" ++ level.asText() ++ "] " ++ scope_prefix;

    // Print the message to stderr, silently ignoring any errors
    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
}

// pub fn main() void {
//     // Using the default scope:
//     std.log.debug("A borderline useless debug log message", .{}); // Won't be printed as log_level is .info
//     std.log.info("Flux capacitor is starting to overheat", .{});

//     // Using scoped logging:
//     const my_project_log = std.log.scoped(.my_project);
//     const nice_library_log = std.log.scoped(.nice_library);
//     const verbose_lib_log = std.log.scoped(.verbose_lib);

//     my_project_log.debug("Starting up", .{}); // Won't be printed as log_level is .info
//     nice_library_log.warn("Something went very wrong, sorry", .{});
//     verbose_lib_log.warn("Added 1 + 1: {}", .{1 + 1}); // Won't be printed as it gets filtered out by our log function
// }
// ```
// Which produces the following output:
// ```
// [info] (default): Flux capacitor is starting to overheat
// [warning] (nice_library): Something went very wrong, sorry
// ```
